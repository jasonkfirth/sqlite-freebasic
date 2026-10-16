/'
    Project: SQLite FreeBASIC port
    ---------------------------------

    File: sqlite3_memsys3.bas

    Purpose:

        Provide SQLite's optional fixed-pool MEMSYS3 allocator.

    Responsibilities:

        - Track the allocator pool as eight-byte blocks with boundary metadata.
        - Maintain small free lists and hashed large free lists.
        - Carve allocations from the key chunk and coalesce adjacent free chunks.
        - Supply the sqlite3_mem_methods callback table selected by config.

    This file intentionally does NOT contain:

        - The default system allocator or the MEMSYS5 buddy allocator.
        - The default system allocator or the MEMSYS5 buddy allocator.
'/

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_memory_methods.bi"
#include once "sqlite3_memsys3_types.bi"
#include once "sqlite3_api_declarations.bi"
#include once "sqlite3_debug_assert.bi"

#ifdef SQLITE_ENABLE_MEMSYS3

/' ------------------------------------------------------------------------- '/
/' Shared MEMSYS3 state '/
/' ------------------------------------------------------------------------- '/

' SQLite uses MX_SMALL=10 and N_HASH=61 for the two free-list classes.
Private Dim Shared mem3 As SqliteMem3Global
Declare Function c2fb_crt_memcpy CDecl Alias "memcpy" (ByVal arg0 As Any Ptr, ByVal arg1 As Const Any Ptr, ByVal arg2 As SQLITE_SIZE_T) As Any Ptr
Declare Function sqlite3ConfigMemStatusEnabled CDecl Alias "sqlite3ConfigMemStatusEnabled" () As SQLITE_C_INT
Declare Function sqlite3MutexAlloc CDecl Alias "sqlite3MutexAlloc" (ByVal mutexType As SQLITE_C_INT) As Any Ptr
Declare Sub memsys3UnlinkFromList CDecl Alias "memsys3UnlinkFromList" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT Ptr)
Declare Sub memsys3Unlink CDecl Alias "memsys3Unlink" (ByVal arg0 As SQLITE_C_UINT)
Declare Sub memsys3LinkIntoList CDecl Alias "memsys3LinkIntoList" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT Ptr)
Declare Sub memsys3Link CDecl Alias "memsys3Link" (ByVal arg0 As SQLITE_C_UINT)
Declare Sub memsys3Enter CDecl Alias "memsys3Enter" ()
Declare Sub memsys3Leave CDecl Alias "memsys3Leave" ()
Declare Sub memsys3OutOfMemory CDecl Alias "memsys3OutOfMemory" (ByVal arg0 As SQLITE_C_INT)
Declare Function memsys3Checkout CDecl Alias "memsys3Checkout" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT) As Any Ptr
Declare Function memsys3FromKeyBlk CDecl Alias "memsys3FromKeyBlk" (ByVal arg0 As SQLITE_C_UINT) As Any Ptr
Declare Sub memsys3Merge CDecl Alias "memsys3Merge" (ByVal arg0 As SQLITE_C_UINT Ptr)
Declare Function memsys3MallocUnsafe CDecl Alias "memsys3MallocUnsafe" (ByVal arg0 As SQLITE_C_INT) As Any Ptr
Declare Sub memsys3FreeUnsafe CDecl Alias "memsys3FreeUnsafe" (ByVal arg0 As Any Ptr)
Declare Function memsys3Size CDecl Alias "memsys3Size" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
Declare Function memsys3Roundup CDecl Alias "memsys3Roundup" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
Declare Function memsys3Malloc CDecl Alias "memsys3Malloc" (ByVal arg0 As SQLITE_C_INT) As Any Ptr
Declare Sub memsys3Free CDecl Alias "memsys3Free" (ByVal arg0 As Any Ptr)
Declare Function memsys3Realloc CDecl Alias "memsys3Realloc" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
Declare Sub memsys3Shutdown CDecl Alias "memsys3Shutdown" (ByVal arg0 As Any Ptr)

/' ------------------------------------------------------------------------- '/
/' C2FB-translated allocator procedures '/
/' ------------------------------------------------------------------------- '/
Private Sub memsys3UnlinkFromList CDecl Alias "memsys3UnlinkFromList" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT Ptr)
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_9 As SQLITE_C_UINT

    local0 = mem3.aPool[arg0].u.list.nextBlock
    local1 = mem3.aPool[arg0].u.list.previousBlock
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
        c2fb_temp_0 = CPtr(SQLITE_C_UINT Ptr, @((*arg1)))
        c2fb_temp_1 = Cast(SQLITE_C_UINT, local0)
        (*c2fb_temp_0) = c2fb_temp_1
    Else
        c2fb_temp_2 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[local1].u.list.nextBlock))
        c2fb_temp_3 = Cast(SQLITE_C_UINT, local0)
        (*c2fb_temp_2) = c2fb_temp_3
    End If
    If local0 Then
        c2fb_temp_4 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[local0].u.list.previousBlock))
        c2fb_temp_5 = Cast(SQLITE_C_UINT, local1)
        (*c2fb_temp_4) = c2fb_temp_5
    End If
    c2fb_temp_6 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[arg0].u.list.nextBlock))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_6) = c2fb_temp_7
    c2fb_temp_8 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[arg0].u.list.previousBlock))
    c2fb_temp_9 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_8) = c2fb_temp_9
End Sub
Private Sub memsys3Unlink CDecl Alias "memsys3Unlink" (ByVal arg0 As SQLITE_C_UINT)
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (mem3.aPool[Cast(SQLITE_C_UINT, (arg0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0 <= Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 10ULL)))))) Then
        memsys3UnlinkFromList(arg0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiSmall(Cast(SQLITE_C_UINT, (local0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))))))
    Else
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local0 Mod Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 61ULL)))))
        local1 = c2fb_temp_1
        memsys3UnlinkFromList(arg0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiHash(local1))))
    End If
End Sub
Private Sub memsys3LinkIntoList CDecl Alias "memsys3LinkIntoList" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT Ptr)
    Dim c2fb_temp_0 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_UINT Ptr
    Dim c2fb_temp_7 As SQLITE_C_UINT

    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[arg0].u.list.nextBlock))
    c2fb_temp_1 = Cast(SQLITE_C_UINT, (*arg1))
    (*c2fb_temp_0) = c2fb_temp_1
    c2fb_temp_2 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[arg0].u.list.previousBlock))
    c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
    (*c2fb_temp_2) = c2fb_temp_3
    If (*arg1) Then
        c2fb_temp_4 = CPtr(SQLITE_C_UINT Ptr, @(mem3.aPool[(*arg1)].u.list.previousBlock))
        c2fb_temp_5 = Cast(SQLITE_C_UINT, arg0)
        (*c2fb_temp_4) = c2fb_temp_5
    End If
    c2fb_temp_6 = CPtr(SQLITE_C_UINT Ptr, @((*arg1)))
    c2fb_temp_7 = Cast(SQLITE_C_UINT, arg0)
    (*c2fb_temp_6) = c2fb_temp_7
End Sub
Private Sub memsys3Link CDecl Alias "memsys3Link" (ByVal arg0 As SQLITE_C_UINT)
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (mem3.aPool[Cast(SQLITE_C_UINT, (arg0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local0 <= Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 10ULL)))))) Then
        memsys3LinkIntoList(arg0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiSmall(Cast(SQLITE_C_UINT, (local0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))))))
    Else
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local0 Mod Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 61ULL)))))
        local1 = c2fb_temp_1
        memsys3LinkIntoList(arg0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiHash(local1))))
    End If
End Sub
Private Sub memsys3Enter CDecl Alias "memsys3Enter" ()
    Dim c2fb_temp_0 As Any Ptr Ptr
    Dim c2fb_temp_1 As Any Ptr

    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((sqlite3ConfigMemStatusEnabled() = Cast(SQLITE_C_INT, &O0ULL))))) AndAlso (-Cast(SQLITE_C_INT, ((mem3.mutex = Cast(SQLITE_C_INT, &O0ULL))))))))) Then
        c2fb_temp_0 = CPtr(Any Ptr Ptr, @(mem3.mutex))
        c2fb_temp_1 = CPtr(Any Ptr, sqlite3MutexAlloc(Cast(SQLITE_C_INT, 3ULL)))
        (*c2fb_temp_0) = c2fb_temp_1
    End If
    sqlite3_mutex_enter(mem3.mutex)
End Sub
Private Sub memsys3Leave CDecl Alias "memsys3Leave" ()
    sqlite3_mutex_leave(mem3.mutex)
End Sub
Private Sub memsys3OutOfMemory CDecl Alias "memsys3OutOfMemory" (ByVal arg0 As SQLITE_C_INT)
    Dim c2fb_temp_0 As SQLITE_C_INT Ptr
    Dim c2fb_temp_1 As SQLITE_C_INT
    Dim c2fb_temp_2 As SQLITE_C_INT Ptr
    Dim c2fb_temp_3 As SQLITE_C_INT

    If (-Cast(SQLITE_C_INT, (mem3.alarmBusy = 0))) Then
        c2fb_temp_0 = CPtr(SQLITE_C_INT Ptr, @(mem3.alarmBusy))
        c2fb_temp_1 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, 1ULL))
        (*c2fb_temp_0) = c2fb_temp_1
        ' C unused-parameter annotation
        sqlite3_mutex_leave(mem3.mutex)
        sqlite3_release_memory(arg0)
        sqlite3_mutex_enter(mem3.mutex)
        c2fb_temp_2 = CPtr(SQLITE_C_INT Ptr, @(mem3.alarmBusy))
        c2fb_temp_3 = Cast(SQLITE_C_INT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = c2fb_temp_3
    End If
End Sub
Private Function memsys3Checkout CDecl Alias "memsys3Checkout" (ByVal arg0 As SQLITE_C_UINT, ByVal arg1 As SQLITE_C_UINT) As Any Ptr
    Dim local0 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As u32 Ptr
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As u32 Ptr
    Dim c2fb_temp_4 As SQLITE_C_UINT
    Dim c2fb_temp_5 As u32 Ptr
    Dim c2fb_temp_6 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_UINT, mem3.aPool[Cast(SQLITE_C_UINT, (arg0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x)
    local0 = c2fb_temp_0
    c2fb_temp_1 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (arg0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
    c2fb_temp_2 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg1 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))) Or (Cast(SQLITE_C_UINT, (local0 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))))))
    (*c2fb_temp_1) = Cast(u32, c2fb_temp_2)
    c2fb_temp_2 = Cast(SQLITE_C_UINT, (*c2fb_temp_1))
    c2fb_temp_3 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg0 + arg1)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.prevSize))
    c2fb_temp_4 = Cast(SQLITE_C_UINT, arg1)
    (*c2fb_temp_3) = Cast(u32, c2fb_temp_4)
    c2fb_temp_4 = Cast(SQLITE_C_UINT, (*c2fb_temp_3))
    c2fb_temp_5 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg0 + arg1)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
    c2fb_temp_6 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_5)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))
    (*c2fb_temp_5) = Cast(u32, c2fb_temp_6)
    c2fb_temp_6 = Cast(SQLITE_C_UINT, (*c2fb_temp_5))
    Return CPtr(SqliteMem3Block Ptr, @(mem3.aPool[arg0]))
End Function
Private Function memsys3FromKeyBlk CDecl Alias "memsys3FromKeyBlk" (ByVal arg0 As SQLITE_C_UINT) As Any Ptr
    Dim local0 As Any Ptr
    Dim c2fb_temp_0 As u32 Ptr
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As u32 Ptr
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As u32 Ptr
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim local2 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_UINT
    Dim c2fb_temp_7 As u32 Ptr
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As u32 Ptr
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As u32 Ptr
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As u32 Ptr
    Dim c2fb_temp_14 As SQLITE_C_UINT
    Dim c2fb_temp_15 As u32 Ptr
    Dim c2fb_temp_16 As SQLITE_C_UINT
    Dim c2fb_temp_17 As SQLITE_C_UINT
    Dim c2fb_temp_18 As u32 Ptr
    Dim c2fb_temp_19 As SQLITE_C_UINT
    Dim c2fb_temp_20 As u32 Ptr
    Dim c2fb_temp_21 As SQLITE_C_UINT

    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg0 >= Cast(SQLITE_C_UINT, (mem3.szKeyBlk - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))))) Then
        local0 = CPtr(Any Ptr, memsys3Checkout(mem3.iKeyBlk, mem3.szKeyBlk))
        c2fb_temp_0 = CPtr(u32 Ptr, @(mem3.iKeyBlk))
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_0) = Cast(u32, c2fb_temp_1)
        c2fb_temp_1 = Cast(SQLITE_C_UINT, (*c2fb_temp_0))
        c2fb_temp_2 = CPtr(u32 Ptr, @(mem3.szKeyBlk))
        c2fb_temp_3 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_2) = Cast(u32, c2fb_temp_3)
        c2fb_temp_3 = Cast(SQLITE_C_UINT, (*c2fb_temp_2))
        c2fb_temp_4 = CPtr(u32 Ptr, @(mem3.mnKeyBlk))
        c2fb_temp_5 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
        (*c2fb_temp_4) = Cast(u32, c2fb_temp_5)
        c2fb_temp_5 = Cast(SQLITE_C_UINT, (*c2fb_temp_4))
        Return local0
    Else
        ' C automatic storage declaration
        ' C automatic storage declaration
        c2fb_temp_6 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (mem3.iKeyBlk + mem3.szKeyBlk)) - arg0)))
        local1 = c2fb_temp_6
        ' C unused-parameter annotation
        c2fb_temp_7 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (mem3.iKeyBlk + mem3.szKeyBlk)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.prevSize))
        c2fb_temp_8 = Cast(SQLITE_C_UINT, arg0)
        (*c2fb_temp_7) = Cast(u32, c2fb_temp_8)
        c2fb_temp_8 = Cast(SQLITE_C_UINT, (*c2fb_temp_7))
        c2fb_temp_9 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (mem3.iKeyBlk + mem3.szKeyBlk)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
        c2fb_temp_10 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_9)) Or Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))
        (*c2fb_temp_9) = Cast(u32, c2fb_temp_10)
        c2fb_temp_10 = Cast(SQLITE_C_UINT, (*c2fb_temp_9))
        c2fb_temp_11 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
        c2fb_temp_12 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (arg0 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) + Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL)))))
        (*c2fb_temp_11) = Cast(u32, c2fb_temp_12)
        c2fb_temp_12 = Cast(SQLITE_C_UINT, (*c2fb_temp_11))
        c2fb_temp_13 = CPtr(u32 Ptr, @(mem3.szKeyBlk))
        c2fb_temp_14 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (*c2fb_temp_13)) - arg0)))
        (*c2fb_temp_13) = Cast(u32, c2fb_temp_14)
        c2fb_temp_14 = Cast(SQLITE_C_UINT, (*c2fb_temp_13))
        c2fb_temp_15 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.prevSize))
        c2fb_temp_16 = Cast(SQLITE_C_UINT, mem3.szKeyBlk)
        (*c2fb_temp_15) = Cast(u32, c2fb_temp_16)
        c2fb_temp_16 = Cast(SQLITE_C_UINT, (*c2fb_temp_15))
        c2fb_temp_17 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (mem3.aPool[Cast(SQLITE_C_UINT, (mem3.iKeyBlk - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))
        local2 = c2fb_temp_17
        c2fb_temp_18 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (mem3.iKeyBlk - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
        c2fb_temp_19 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (mem3.szKeyBlk * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) Or local2)))
        (*c2fb_temp_18) = Cast(u32, c2fb_temp_19)
        c2fb_temp_19 = Cast(SQLITE_C_UINT, (*c2fb_temp_18))
        If (-Cast(SQLITE_C_INT, ((mem3.szKeyBlk < mem3.mnKeyBlk)))) Then
            c2fb_temp_20 = CPtr(u32 Ptr, @(mem3.mnKeyBlk))
            c2fb_temp_21 = Cast(SQLITE_C_UINT, mem3.szKeyBlk)
            (*c2fb_temp_20) = Cast(u32, c2fb_temp_21)
            c2fb_temp_21 = Cast(SQLITE_C_UINT, (*c2fb_temp_20))
        End If
        Return CPtr(Any Ptr, CPtr(SqliteMem3Block Ptr, @(mem3.aPool[local1])))
    End If
End Function
Private Sub memsys3Merge CDecl Alias "memsys3Merge" (ByVal arg0 As SQLITE_C_UINT Ptr)
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim local2 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_UINT
    Dim local4 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_UINT
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_UINT
    Dim c2fb_temp_7 As SQLITE_C_UINT
    Dim c2fb_temp_8 As u32 Ptr
    Dim c2fb_temp_9 As SQLITE_C_UINT
    Dim c2fb_temp_10 As u32 Ptr
    Dim c2fb_temp_11 As SQLITE_C_UINT
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As SQLITE_C_UINT
    Dim c2fb_temp_14 As u32 Ptr
    Dim c2fb_temp_15 As SQLITE_C_UINT
    Dim c2fb_temp_16 As u32 Ptr
    Dim c2fb_temp_17 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = Cast(SQLITE_C_UINT, (*arg0))
    local3 = c2fb_temp_0
    While (-Cast(SQLITE_C_INT, ((local3 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))
        c2fb_temp_2 = Cast(SQLITE_C_UINT, mem3.aPool[local3].u.list.nextBlock)
        local0 = c2fb_temp_2
        c2fb_temp_3 = Cast(SQLITE_C_UINT, mem3.aPool[Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x)
        local2 = c2fb_temp_3
        ' C unused-parameter annotation
        If (-Cast(SQLITE_C_INT, (((Cast(SQLITE_C_UINT, (local2 And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))) = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            memsys3UnlinkFromList(local3, arg0)
            ' C unused-parameter annotation
            c2fb_temp_4 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local3 - mem3.aPool[Cast(SQLITE_C_UINT, (local3 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.prevSize)))
            local1 = c2fb_temp_4
            If (-Cast(SQLITE_C_INT, ((local1 = local0)))) Then
                c2fb_temp_5 = Cast(SQLITE_C_UINT, mem3.aPool[local1].u.list.nextBlock)
                local0 = c2fb_temp_5
            End If
            memsys3Unlink(local1)
            c2fb_temp_6 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (local3 + Cast(SQLITE_C_UINT, (local2 \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))) - local1)))
            local2 = c2fb_temp_6
            c2fb_temp_7 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (mem3.aPool[Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))
            local4 = c2fb_temp_7
            c2fb_temp_8 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x))
            c2fb_temp_9 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (local2 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) Or local4)))
            (*c2fb_temp_8) = Cast(u32, c2fb_temp_9)
            c2fb_temp_9 = Cast(SQLITE_C_UINT, (*c2fb_temp_8))
            c2fb_temp_10 = CPtr(u32 Ptr, @(mem3.aPool[Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, (local1 + local2)) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.prevSize))
            c2fb_temp_11 = Cast(SQLITE_C_UINT, local2)
            (*c2fb_temp_10) = Cast(u32, c2fb_temp_11)
            c2fb_temp_11 = Cast(SQLITE_C_UINT, (*c2fb_temp_10))
            memsys3Link(local1)
            c2fb_temp_12 = Cast(SQLITE_C_UINT, local1)
            local3 = c2fb_temp_12
        Else
            c2fb_temp_13 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local2 \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))))
            local2 = c2fb_temp_13
        End If
        If (-Cast(SQLITE_C_INT, ((local2 > mem3.szKeyBlk)))) Then
            c2fb_temp_14 = CPtr(u32 Ptr, @(mem3.iKeyBlk))
            c2fb_temp_15 = Cast(SQLITE_C_UINT, local3)
            (*c2fb_temp_14) = Cast(u32, c2fb_temp_15)
            c2fb_temp_15 = Cast(SQLITE_C_UINT, (*c2fb_temp_14))
            c2fb_temp_16 = CPtr(u32 Ptr, @(mem3.szKeyBlk))
            c2fb_temp_17 = Cast(SQLITE_C_UINT, local2)
            (*c2fb_temp_16) = Cast(u32, c2fb_temp_17)
            c2fb_temp_17 = Cast(SQLITE_C_UINT, (*c2fb_temp_16))
        End If
    c2fb_flow_1:
        c2fb_temp_1 = Cast(SQLITE_C_UINT, local0)
        local3 = c2fb_temp_1
    Wend
    c2fb_flow_0:
End Sub
Private Function memsys3MallocUnsafe CDecl Alias "memsys3MallocUnsafe" (ByVal arg0 As SQLITE_C_INT) As Any Ptr
    Dim local0 As SQLITE_C_UINT
    Dim local1 As SQLITE_C_UINT
    Dim local2 As SQLITE_C_UINT
    Dim c2fb_temp_0 As SQLITE_C_UINT
    Dim c2fb_temp_1 As SQLITE_C_UINT
    Dim c2fb_temp_2 As SQLITE_C_UINT
    Dim local3 As SQLITE_C_INT
    Dim c2fb_temp_3 As SQLITE_C_UINT
    Dim c2fb_temp_4 As SQLITE_C_UINT
    Dim c2fb_temp_5 As SQLITE_C_UINT
    Dim c2fb_temp_6 As SQLITE_C_UINT
    Dim c2fb_temp_7 As u32 Ptr
    Dim c2fb_temp_8 As SQLITE_C_UINT
    Dim c2fb_temp_9 As u32 Ptr
    Dim c2fb_temp_10 As SQLITE_C_UINT
    Dim c2fb_temp_11 As SQLITE_C_UINT
    Dim c2fb_temp_12 As SQLITE_C_UINT
    Dim c2fb_temp_13 As SQLITE_C_UINT
    Dim c2fb_temp_14 As SQLITE_C_UINT

    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C automatic storage declaration
    ' C unused-parameter annotation
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((arg0 <= Cast(SQLITE_C_INT, 12ULL))))) Then
        c2fb_temp_0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))
        local1 = c2fb_temp_0
    Else
        c2fb_temp_1 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0 + Cast(SQLITE_C_INT, 11ULL)))) \ Cast(SQLITE_C_INT, 8ULL))))
        local1 = c2fb_temp_1
    End If
    ' C unused-parameter annotation
    If (-Cast(SQLITE_C_INT, ((local1 <= Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 10ULL)))))) Then
        c2fb_temp_2 = Cast(SQLITE_C_UINT, mem3.aiSmall(Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))))
        local0 = c2fb_temp_2
        If (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL)))))) Then
            memsys3UnlinkFromList(local0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiSmall(Cast(SQLITE_C_UINT, (local1 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL))))))))
            Return CPtr(Any Ptr, memsys3Checkout(local0, local1))
        End If
    Else
        local3 = Cast(SQLITE_C_UINT, (local1 Mod Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 61ULL))))
        c2fb_temp_3 = Cast(SQLITE_C_UINT, mem3.aiHash(local3))
        local0 = c2fb_temp_3
        While (-Cast(SQLITE_C_INT, ((local0 > Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))))))
            If (-Cast(SQLITE_C_INT, ((Cast(SQLITE_C_UINT, (mem3.aPool[Cast(SQLITE_C_UINT, (local0 - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 1ULL))))].u.hdr.size4x \ Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL)))) = local1)))) Then
                memsys3UnlinkFromList(local0, CPtr(SQLITE_C_UINT Ptr, @(mem3.aiHash(local3))))
                Return CPtr(Any Ptr, memsys3Checkout(local0, local1))
            End If
        c2fb_flow_1:
            c2fb_temp_4 = Cast(SQLITE_C_UINT, mem3.aPool[local0].u.list.nextBlock)
            local0 = c2fb_temp_4
        Wend
        c2fb_flow_0:
    End If
    If (-Cast(SQLITE_C_INT, ((mem3.szKeyBlk >= local1)))) Then
        Return CPtr(Any Ptr, memsys3FromKeyBlk(local1))
    End If
    c2fb_temp_5 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local1 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 16ULL)))))
    local2 = c2fb_temp_5
    While (-Cast(SQLITE_C_INT, ((local2 < (Cast(SQLITE_C_UINT, (mem3.nPool * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 16ULL)))))))))
        memsys3OutOfMemory(local2)
        If mem3.iKeyBlk Then
            memsys3Link(mem3.iKeyBlk)
            c2fb_temp_7 = CPtr(u32 Ptr, @(mem3.iKeyBlk))
            c2fb_temp_8 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_7) = Cast(u32, c2fb_temp_8)
            c2fb_temp_8 = Cast(SQLITE_C_UINT, (*c2fb_temp_7))
            c2fb_temp_9 = CPtr(u32 Ptr, @(mem3.szKeyBlk))
            c2fb_temp_10 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
            (*c2fb_temp_9) = Cast(u32, c2fb_temp_10)
            c2fb_temp_10 = Cast(SQLITE_C_UINT, (*c2fb_temp_9))
        End If
        c2fb_temp_11 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_11
        While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 61ULL))))))
            memsys3Merge(CPtr(SQLITE_C_UINT Ptr, @(mem3.aiHash(local0))))
        c2fb_flow_5:
            c2fb_temp_12 = local0
            local0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_12 + 1)))
        Wend
        c2fb_flow_4:
        c2fb_temp_13 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, &O0ULL))
        local0 = c2fb_temp_13
        While (-Cast(SQLITE_C_INT, ((local0 < Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Cast(SQLITE_C_INT, 10ULL) - Cast(SQLITE_C_INT, 1ULL))))))))
            memsys3Merge(CPtr(SQLITE_C_UINT Ptr, @(mem3.aiSmall(local0))))
        c2fb_flow_7:
            c2fb_temp_14 = local0
            local0 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (c2fb_temp_14 + 1)))
        Wend
        c2fb_flow_6:
        If mem3.szKeyBlk Then
            memsys3Unlink(mem3.iKeyBlk)
            If (-Cast(SQLITE_C_INT, ((mem3.szKeyBlk >= local1)))) Then
                Return CPtr(Any Ptr, memsys3FromKeyBlk(local1))
            End If
        End If
    c2fb_flow_3:
        c2fb_temp_6 = Cast(SQLITE_C_UINT, Cast(SQLITE_C_UINT, (local2 * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))))
        local2 = c2fb_temp_6
    Wend
    c2fb_flow_2:
    Return Cast(SQLITE_C_INT, &O0ULL)
End Function
Private Sub memsys3FreeUnsafe CDecl Alias "memsys3FreeUnsafe" (ByVal pOld As Any Ptr)
    If pOld = 0 OrElse mem3.aPool = 0 OrElse mem3.nPool < 2 Then Return

    Dim pBlock As SqliteMem3Block Ptr = CPtr(SqliteMem3Block Ptr, pOld)
    Dim byteOffset As sqlite3_int64 = _
        CPtr(UByte Ptr, pBlock) - CPtr(UByte Ptr, mem3.aPool)
    If byteOffset <= 0 OrElse _
       byteOffset Mod SizeOf(SqliteMem3Block) <> 0 Then Return

    Dim blockIndex64 As sqlite3_int64 = byteOffset \ SizeOf(SqliteMem3Block)
    If blockIndex64 < 1 OrElse blockIndex64 >= mem3.nPool Then Return
    Dim i As u32 = CUInt(blockIndex64)
    Dim size4x As u32 = mem3.aPool[i - 1].u.hdr.size4x
    If (size4x And 1) = 0 Then Return

    Dim size As u32 = size4x \ 4
    If size < 2 OrElse CULngInt(i) + CULngInt(size) > _
       CULngInt(mem3.nPool) + 1 Then Return

    mem3.aPool[i - 1].u.hdr.size4x And= Not 1
    mem3.aPool[i + size - 1].u.hdr.prevSize = size
    mem3.aPool[i + size - 1].u.hdr.size4x And= Not 2
    memsys3Link(i)

    If mem3.iKeyBlk <> 0 Then
        While (mem3.aPool[mem3.iKeyBlk - 1].u.hdr.size4x And 2) = 0
            Dim previousSize As u32 = _
                mem3.aPool[mem3.iKeyBlk - 1].u.hdr.prevSize
            If previousSize = 0 OrElse previousSize >= mem3.iKeyBlk Then Return
            mem3.iKeyBlk -= previousSize
            mem3.szKeyBlk += previousSize
            memsys3Unlink(mem3.iKeyBlk)
            Dim previousFlags As u32 = _
                mem3.aPool[mem3.iKeyBlk - 1].u.hdr.size4x And 2
            mem3.aPool[mem3.iKeyBlk - 1].u.hdr.size4x = _
                (mem3.szKeyBlk * 4) Or previousFlags
            mem3.aPool[mem3.iKeyBlk + mem3.szKeyBlk - 1].u.hdr.prevSize = _
                mem3.szKeyBlk
        Wend

        Dim keyFlags As u32 = _
            mem3.aPool[mem3.iKeyBlk - 1].u.hdr.size4x And 2
        While (mem3.aPool[mem3.iKeyBlk + mem3.szKeyBlk - 1].u.hdr.size4x And 1) = 0
            Dim nextKeyBlock As u32 = mem3.iKeyBlk + mem3.szKeyBlk
            If nextKeyBlock > mem3.nPool Then Exit While
            Dim nextSize As u32 = _
                mem3.aPool[nextKeyBlock - 1].u.hdr.size4x \ 4
            If nextSize < 2 OrElse _
               CULngInt(nextKeyBlock) + CULngInt(nextSize) > _
                   CULngInt(mem3.nPool) + 1 Then Exit While
            memsys3Unlink(nextKeyBlock)
            mem3.szKeyBlk += nextSize
            mem3.aPool[mem3.iKeyBlk - 1].u.hdr.size4x = _
                (mem3.szKeyBlk * 4) Or keyFlags
            mem3.aPool[mem3.iKeyBlk + mem3.szKeyBlk - 1].u.hdr.prevSize = _
                mem3.szKeyBlk
        Wend
    End If
End Sub
Private Function memsys3Size CDecl Alias "memsys3Size" (ByVal arg0 As Any Ptr) As SQLITE_C_INT
    Dim local0 As SqliteMem3Block Ptr
    Dim c2fb_temp_0 As SqliteMem3Block Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(SqliteMem3Block Ptr, arg0)
    local0 = c2fb_temp_0
    ' C unused-parameter annotation
    Return Cast(SQLITE_C_UINT, (Cast(SQLITE_C_UINT, ((Cast(SQLITE_C_UINT, (local0[Cast(SQLITE_C_INT, (-Cast(SQLITE_C_INT, 1ULL)))].u.hdr.size4x And Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, 3ULL))))))) * Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 2ULL)))) - Cast(SQLITE_C_UINT, Cast(SQLITE_C_INT, 4ULL))))
End Function
Private Function memsys3Roundup CDecl Alias "memsys3Roundup" (ByVal arg0 As SQLITE_C_INT) As SQLITE_C_INT
    If (-Cast(SQLITE_C_INT, ((arg0 <= Cast(SQLITE_C_INT, 12ULL))))) Then
        Return Cast(SQLITE_C_INT, 12ULL)
    Else
        Return Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, ((Cast(SQLITE_C_INT, (arg0 + Cast(SQLITE_C_INT, 11ULL)))) And Cast(SQLITE_C_INT, (Not Cast(SQLITE_C_INT, 7ULL)))))) - Cast(SQLITE_C_INT, 4ULL)))
    End If
End Function
Private Function memsys3Malloc CDecl Alias "memsys3Malloc" (ByVal arg0 As SQLITE_C_INT) As Any Ptr
    Dim local0 As sqlite3_int64 Ptr
    Dim c2fb_temp_0 As sqlite3_int64 Ptr

    ' C automatic storage declaration
    ' C unused-parameter annotation
    memsys3Enter()
    c2fb_temp_0 = CPtr(sqlite3_int64 Ptr, CPtr(Any Ptr, memsys3MallocUnsafe(arg0)))
    local0 = c2fb_temp_0
    memsys3Leave()
    Return CPtr(Any Ptr, local0)
End Function
Private Sub memsys3Free CDecl Alias "memsys3Free" (ByVal arg0 As Any Ptr)
    ' C unused-parameter annotation
    memsys3Enter()
    memsys3FreeUnsafe(arg0)
    memsys3Leave()
End Sub
Private Function memsys3Realloc CDecl Alias "memsys3Realloc" (ByVal arg0 As Any Ptr, ByVal arg1 As SQLITE_C_INT) As Any Ptr
    Dim local0 As SQLITE_C_INT
    Dim local1 As Any Ptr
    Dim c2fb_temp_0 As SQLITE_C_INT
    Dim c2fb_temp_1 As Any Ptr
    Dim c2fb_temp_2 As Any Ptr
    Dim c2fb_temp_3 As Any Ptr

    ' C automatic storage declaration
    ' C automatic storage declaration
    If (-Cast(SQLITE_C_INT, ((arg0 = Cast(SQLITE_C_INT, &O0ULL))))) Then
        Return CPtr(Any Ptr, sqlite3_malloc(arg1))
    End If
    If (-Cast(SQLITE_C_INT, ((arg1 <= Cast(SQLITE_C_INT, &O0ULL))))) Then
        sqlite3_free(arg0)
        Return Cast(SQLITE_C_INT, &O0ULL)
    End If
    c2fb_temp_0 = Cast(SQLITE_C_INT, memsys3Size(arg0))
    local0 = c2fb_temp_0
    If (-Cast(SQLITE_C_INT, (((-Cast(SQLITE_C_INT, ((arg1 <= local0)))) AndAlso (-Cast(SQLITE_C_INT, ((arg1 >= Cast(SQLITE_C_INT, (local0 - Cast(SQLITE_C_INT, 128ULL))))))))))) Then
        Return arg0
    End If
    memsys3Enter()
    c2fb_temp_1 = CPtr(Any Ptr, memsys3MallocUnsafe(arg1))
    local1 = c2fb_temp_1
    If local1 Then
        If (-Cast(SQLITE_C_INT, ((local0 < arg1)))) Then
            c2fb_temp_2 = CPtr(Any Ptr, c2fb_crt_memcpy(local1, CPtr(Const Any Ptr, arg0), local0))
        Else
            c2fb_temp_3 = CPtr(Any Ptr, c2fb_crt_memcpy(local1, CPtr(Const Any Ptr, arg0), arg1))
        End If
        memsys3FreeUnsafe(arg0)
    End If
    memsys3Leave()
    Return local1
End Function
Private Sub memsys3Shutdown CDecl Alias "memsys3Shutdown" (ByVal arg0 As Any Ptr)
    Dim c2fb_temp_0 As Any Ptr Ptr
    Dim c2fb_temp_1 As Any Ptr

    ' C unused-parameter annotation
    c2fb_temp_0 = CPtr(Any Ptr Ptr, @(mem3.mutex))
    c2fb_temp_1 = CPtr(Any Ptr, Cast(Integer, Cast(SQLITE_C_INT, &O0ULL)))
    (*c2fb_temp_0) = c2fb_temp_1
    Return
End Sub
/'
    -------------------------------------------------------------------------
    Debug pool report
    -------------------------------------------------------------------------
'/
#ifdef SQLITE_DEBUG
Extern "C"
    Extern memsys3DebugStdout Alias "stdout" As Any Ptr
    Extern memsys3DebugStderr Alias "stderr" As Any Ptr
    Declare Function memsys3DebugFopen CDecl Alias "fopen" ( _
        ByVal zFilename As Const ZString Ptr, _
        ByVal zMode As Const ZString Ptr _
    ) As Any Ptr
    Declare Function memsys3DebugFprintf CDecl Alias "fprintf" ( _
        ByVal pStream As Any Ptr, _
        ByVal zFormat As Const ZString Ptr, _
        ... _
    ) As SQLITE_C_INT
    Declare Function memsys3DebugFflush CDecl Alias "fflush" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
    Declare Function memsys3DebugFclose CDecl Alias "fclose" ( _
        ByVal pStream As Any Ptr _
    ) As SQLITE_C_INT
End Extern
#endif

Sub sqlite3Memsys3Dump CDecl Alias "sqlite3Memsys3Dump" ( _
    ByVal zFilename As Const ZString Ptr _
)
#ifdef SQLITE_DEBUG
    Dim pOutput As Any Ptr
    Dim i As SQLITE_C_UINT
    Dim j As SQLITE_C_UINT
    Dim chunkSize4x As SQLITE_C_UINT
    Dim chunkBlocks As SQLITE_C_UINT
    Dim tailIndex As SQLITE_C_UINT
    Dim zKeyMarker As Const ZString Ptr
    Dim blockBytes As SQLITE_C_UINT = SizeOf(SqliteMem3Block)

    If zFilename = 0 OrElse CPtr(Const UByte Ptr, zFilename)[0] = 0 Then
        pOutput = memsys3DebugStdout
    Else
        pOutput = memsys3DebugFopen(zFilename, StrPtr(!"w"))
        If pOutput = 0 Then
            memsys3DebugFprintf( _
                memsys3DebugStderr, _
                StrPtr(!"** Unable to output memory debug output log: %s **\n"), _
                zFilename _
            )
            Return
        End If
    End If

    memsys3Enter()
    memsys3DebugFprintf(pOutput, StrPtr(!"CHUNKS:\n"))

    i = 1
    While i <= mem3.nPool
        chunkSize4x = mem3.aPool[i - 1].u.hdr.size4x
        ' The header stores four times the actual number of pool blocks.
        chunkBlocks = chunkSize4x \ 4

        ' Reject a corrupt chunk length before using it to address the pool tail.
        If chunkBlocks <= 1 OrElse chunkBlocks > mem3.nPool - i + 1 Then
            memsys3DebugFprintf( _
                pOutput, StrPtr(!"%p size error\n"), @mem3.aPool[i])
            sqlite3DebugAssert(StrPtr("MEMSYS3 chunk size is within the pool"))
            Exit While
        End If

        tailIndex = i + chunkBlocks - 1
        If (chunkSize4x And 1) = 0 AndAlso _
           mem3.aPool[tailIndex].u.hdr.prevSize <> chunkBlocks Then
            memsys3DebugFprintf( _
                pOutput, StrPtr(!"%p tail size does not match\n"), _
                @mem3.aPool[i])
            sqlite3DebugAssert(StrPtr("MEMSYS3 chunk tail size matches"))
            Exit While
        End If

        ' Bit 1 in the tail header records checkout state for the final block.
        If ((mem3.aPool[tailIndex].u.hdr.size4x And 2) Shr 1) <> _
           (chunkSize4x And 1) Then
            memsys3DebugFprintf( _
                pOutput, StrPtr(!"%p tail checkout bit is incorrect\n"), _
                @mem3.aPool[i])
            sqlite3DebugAssert(StrPtr("MEMSYS3 chunk tail checkout bit matches"))
            Exit While
        End If

        If (chunkSize4x And 1) <> 0 Then
            memsys3DebugFprintf( _
                pOutput, StrPtr(!"%p %6d bytes checked out\n"), _
                @mem3.aPool[i], _
                Cast(SQLITE_C_INT, chunkBlocks * blockBytes - blockBytes))
        Else
            If i = mem3.iKeyBlk Then
                zKeyMarker = StrPtr(!" **key**")
            Else
                zKeyMarker = StrPtr(!"")
            End If
            memsys3DebugFprintf( _
                pOutput, StrPtr(!"%p %6d bytes free%s\n"), _
                @mem3.aPool[i], _
                Cast(SQLITE_C_INT, chunkBlocks * blockBytes - blockBytes), _
                zKeyMarker)
        End If

        i += chunkBlocks
    Wend

    For i = LBound(mem3.aiSmall) To UBound(mem3.aiSmall)
        If mem3.aiSmall(i) = 0 Then Continue For
        memsys3DebugFprintf(pOutput, StrPtr(!"small(%2d):"), i)
        j = mem3.aiSmall(i)
        While j > 0
            memsys3DebugFprintf( _
                pOutput, StrPtr(!" %p(%d)"), @mem3.aPool[j], _
                Cast(SQLITE_C_INT, _
                    (mem3.aPool[j - 1].u.hdr.size4x \ 4) * _
                    blockBytes - blockBytes))
            j = mem3.aPool[j].u.list.nextBlock
        Wend
        memsys3DebugFprintf(pOutput, StrPtr(!"\n"))
    Next

    For i = LBound(mem3.aiHash) To UBound(mem3.aiHash)
        If mem3.aiHash(i) = 0 Then Continue For
        memsys3DebugFprintf(pOutput, StrPtr(!"hash(%2d):"), i)
        j = mem3.aiHash(i)
        While j > 0
            memsys3DebugFprintf( _
                pOutput, StrPtr(!" %p(%d)"), @mem3.aPool[j], _
                Cast(SQLITE_C_INT, _
                    (mem3.aPool[j - 1].u.hdr.size4x \ 4) * _
                    blockBytes - blockBytes))
            j = mem3.aPool[j].u.list.nextBlock
        Wend
        memsys3DebugFprintf(pOutput, StrPtr(!"\n"))
    Next

    memsys3DebugFprintf(pOutput, StrPtr(!"key=%d\n"), mem3.iKeyBlk)
    memsys3DebugFprintf( _
        pOutput, StrPtr(!"nowUsed=%d\n"), _
        Cast(SQLITE_C_INT, (mem3.nPool - mem3.szKeyBlk) * blockBytes))
    memsys3DebugFprintf( _
        pOutput, StrPtr(!"mxUsed=%d\n"), _
        Cast(SQLITE_C_INT, (mem3.nPool - mem3.mnKeyBlk) * blockBytes))
    sqlite3_mutex_leave(mem3.mutex)

    If pOutput = memsys3DebugStdout Then
        memsys3DebugFflush(memsys3DebugStdout)
    Else
        memsys3DebugFclose(pOutput)
    End If
#else
    ' C unused-parameter annotation
#endif
End Sub

/' ------------------------------------------------------------------------- '/
/' Initialization and callback table '/
/' ------------------------------------------------------------------------- '/

Private Function memsys3Init CDecl (ByVal pUnused As Any Ptr) As SQLITE_C_INT
    Dim pHeap As Any Ptr = 0
    Dim heapSize As SQLITE_C_INT = 0
    Dim minimumRequest As SQLITE_C_INT = 0
    sqlite3ConfigGetHeap(@pHeap, @heapSize, @minimumRequest)

    If pHeap = 0 OrElse heapSize < SizeOf(SqliteMem3Block) * 4 OrElse _
       SizeOf(SqliteMem3Block) <> 8 Then Return SQLITE_ERROR

    Dim poolCount As sqlite3_int64 = _
        (CLngInt(heapSize) \ SizeOf(SqliteMem3Block)) - 2
    If poolCount < 2 OrElse poolCount > &H3FFFFFFF Then Return SQLITE_ERROR

    mem3.aPool = CPtr(SqliteMem3Block Ptr, pHeap)
    mem3.nPool = CUInt(poolCount)
    mem3.szKeyBlk = mem3.nPool
    mem3.mnKeyBlk = mem3.szKeyBlk
    mem3.iKeyBlk = 1
    mem3.alarmBusy = 0

    mem3.aPool[0].u.hdr.size4x = (mem3.szKeyBlk Shl 2) Or 2
    mem3.aPool[mem3.nPool].u.hdr.prevSize = mem3.nPool
    mem3.aPool[mem3.nPool].u.hdr.size4x = 1
    Return SQLITE_OK
End Function

Private Dim Shared As Const SqliteMemMethods memsys3Methods = _
    Type<SqliteMemMethods>( _
        ProcPtr(memsys3Malloc), _
        ProcPtr(memsys3Free), _
        ProcPtr(memsys3Realloc), _
        ProcPtr(memsys3Size), _
        ProcPtr(memsys3Roundup), _
        ProcPtr(memsys3Init), _
        ProcPtr(memsys3Shutdown), _
        0 _
    )

Function sqlite3MemGetMemsys3 CDecl Alias "sqlite3MemGetMemsys3" () _
    As Const SqliteMemMethods Ptr Export
    Return @memsys3Methods
End Function

#endif


/' end of sqlite3_memsys3.bas '/
