/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memjournal.bas

    Purpose:

        Store rollback journal bytes in linked memory chunks and spill them
        to a VFS file when the configured threshold is exceeded.

    Responsibilities:

        - Implement the sqlite3_file methods for an in-memory journal.
        - Preserve journal contents when switching from memory to a real file.
        - Manage chunk allocation, reads, writes, truncation, and close.

    This file intentionally does NOT contain:

        - Database page serialization or transaction decisions.
        - The VFS implementation used after a journal spills to disk.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_mutex.bi"
#include once "sqlite3_memjournal.bi"

Declare Function sqlite3Malloc CDecl Alias "sqlite3Malloc" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Function sqlite3MallocZero CDecl Alias "sqlite3MallocZero" (ByVal nByte As sqlite3_uint64) As Any Ptr
Declare Sub sqlite3_free CDecl Alias "sqlite3_free" (ByVal p As Any Ptr)

Private Const MEMJOURNAL_DEFAULT_FILE_CHUNK_SIZE As Long = 1024

/' ------------------------------------------------------------------------- '/
/' Memory journal layouts '/
/' ------------------------------------------------------------------------- '/

Private Type MemJournalFileChunk
    pNext As MemJournalFileChunk Ptr
    zChunk(0 To 7) As UByte
End Type

Private Type MemJournalFilePoint
    iOffset As sqlite3_int64
    pChunk As MemJournalFileChunk Ptr
End Type

Private Type MemJournal
    pMethods As sqlite3_io_methods Ptr
    nChunkSize As SQLITE_C_INT
    nSpill As SQLITE_C_INT
    pFirst As MemJournalFileChunk Ptr
    endpoint As MemJournalFilePoint
    readpoint As MemJournalFilePoint
    flags As SQLITE_C_INT
    pVfs As sqlite3_vfs Ptr
    zJournal As Any Ptr
End Type

Private Dim Shared memJournalMethods As sqlite3_io_methods
Private Dim Shared memJournalMethodsReady As SQLITE_C_INT

Declare Function memjrnlClose CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
Declare Function memjrnlRead CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memjrnlWrite CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memjrnlTruncate CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT
Declare Function memjrnlSync CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function memjrnlFileSize CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT
Declare Sub memjrnlSetMethods()

/' ------------------------------------------------------------------------- '/
/' Shared helpers '/
/' ------------------------------------------------------------------------- '/

Private Function memjrnlInitializeMethods() As SQLITE_C_INT
    ' Pager calls serialize an individual journal. This static mutex only
    ' publishes the shared VFS method table once across concurrent opens.
    Dim pMutex As Any Ptr = sqlite3MutexAlloc(SQLITE_MUTEX_STATIC_MAIN)
    If pMutex = 0 Then
        ' A null static mutex also occurs after runtime SINGLETHREAD config.
        ' With mutexes disabled, no other thread can race this initialization.
        If memJournalMethodsReady = 0 Then memjrnlSetMethods()
        Return SQLITE_OK
    End If
    sqlite3_mutex_enter(pMutex)
    If memJournalMethodsReady = 0 Then memjrnlSetMethods()
    sqlite3_mutex_leave(pMutex)
    Return SQLITE_OK
End Function

Private Sub memjrnlSetMethods()
    memJournalMethods.iVersion = 1
    memJournalMethods.xClose = @memjrnlClose
    memJournalMethods.xRead = @memjrnlRead
    memJournalMethods.xWrite = @memjrnlWrite
    memJournalMethods.xTruncate = @memjrnlTruncate
    memJournalMethods.xSync = @memjrnlSync
    memJournalMethods.xFileSize = @memjrnlFileSize
    memJournalMethods.xLock = 0
    memJournalMethods.xUnlock = 0
    memJournalMethods.xCheckReservedLock = 0
    memJournalMethods.xFileControl = 0
    memJournalMethods.xSectorSize = 0
    memJournalMethods.xDeviceCharacteristics = 0
    memJournalMethods.xShmMap = 0
    memJournalMethods.xShmLock = 0
    memJournalMethods.xShmBarrier = 0
    memJournalMethods.xShmUnmap = 0
    memJournalMethods.xFetch = 0
    memJournalMethods.xUnfetch = 0
    memJournalMethodsReady = 1
End Sub

Private Function memjrnlChunkAllocationSize(ByVal chunkSize As SQLITE_C_INT) As sqlite3_uint64
    If chunkSize < 8 Then Return 0
    Dim extraBytes As sqlite3_uint64 = CULngInt(chunkSize - 8)
    If extraBytes > SQLITE_MAX_ALLOCATION_SIZE - SizeOf(MemJournalFileChunk) Then Return 0
    Return SizeOf(MemJournalFileChunk) + extraBytes
End Function

Private Sub memjrnlCopyBytes( _
    ByVal pDestination As UByte Ptr, _
    ByVal pSource As Const UByte Ptr, _
    ByVal amount As SQLITE_C_INT _
)
    If pDestination = 0 OrElse pSource = 0 OrElse amount <= 0 Then Exit Sub
    For i As SQLITE_C_INT = 0 To amount - 1
        pDestination[i] = pSource[i]
    Next
End Sub

Private Sub memjrnlFreeChunks(ByVal pChunk As MemJournalFileChunk Ptr)
    While pChunk <> 0
        Dim pNext As MemJournalFileChunk Ptr = pChunk->pNext
        sqlite3_free(pChunk)
        pChunk = pNext
    Wend
End Sub

/' ------------------------------------------------------------------------- '/
/' sqlite3_file methods '/
/' ------------------------------------------------------------------------- '/

Private Function memjrnlRead CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse (amount > 0 AndAlso pBuffer = 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pFile)
    If pJournal->nChunkSize <= 0 Then Return SQLITE_IOERR_READ
    If amount = 0 Then Return SQLITE_OK
    If offset > &H7FFFFFFFFFFFFFFF - amount Then Return SQLITE_IOERR_SHORT_READ
    If offset + amount > pJournal->endpoint.iOffset Then Return SQLITE_IOERR_SHORT_READ

    Dim pChunk As MemJournalFileChunk Ptr = 0
    Dim chunkStart As sqlite3_int64 = 0
    If offset <> 0 AndAlso pJournal->readpoint.iOffset = offset AndAlso pJournal->readpoint.pChunk <> 0 Then
        pChunk = pJournal->readpoint.pChunk
        chunkStart = offset - (offset Mod pJournal->nChunkSize)
    Else
        pChunk = pJournal->pFirst
        While pChunk <> 0 AndAlso chunkStart + pJournal->nChunkSize <= offset
            pChunk = pChunk->pNext
            chunkStart += pJournal->nChunkSize
        Wend
    End If
    If pChunk = 0 Then Return SQLITE_CORRUPT

    Dim pOutput As UByte Ptr = CPtr(UByte Ptr, pBuffer)
    Dim remaining As SQLITE_C_INT = amount
    Dim chunkOffset As SQLITE_C_INT = CInt(offset Mod pJournal->nChunkSize)
    While remaining > 0
        If pChunk = 0 Then Return SQLITE_CORRUPT
        Dim chunkSpace As SQLITE_C_INT = pJournal->nChunkSize - chunkOffset
        Dim copySize As SQLITE_C_INT = IIf(remaining < chunkSpace, remaining, chunkSpace)
        memjrnlCopyBytes(pOutput, CPtr(Const UByte Ptr, @pChunk->zChunk(0) + chunkOffset), copySize)
        pOutput += copySize
        remaining -= copySize
        chunkOffset = 0
        If remaining > 0 Then pChunk = pChunk->pNext
    Wend

    Dim endOffset As sqlite3_int64 = offset + amount
    If endOffset < pJournal->endpoint.iOffset Then
        If endOffset Mod pJournal->nChunkSize = 0 Then
            pJournal->readpoint.pChunk = pChunk->pNext
        Else
            pJournal->readpoint.pChunk = pChunk
        End If
        pJournal->readpoint.iOffset = endOffset
    Else
        pJournal->readpoint.iOffset = 0
        pJournal->readpoint.pChunk = 0
    End If
    Return SQLITE_OK
End Function

Private Function memjrnlCreateFile(ByVal pJournal As MemJournal Ptr) As SQLITE_C_INT
    If pJournal = 0 OrElse pJournal->pVfs = 0 OrElse pJournal->nChunkSize < 8 Then Return SQLITE_MISUSE

    Dim original As MemJournal = *pJournal
    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, pJournal)
    For i As Long = 0 To SizeOf(MemJournal) - 1
        pBytes[i] = 0
    Next

    Dim outFlags As SQLITE_C_INT = 0
    Dim pRealFile As sqlite3_file Ptr = CPtr(sqlite3_file Ptr, pJournal)
    Dim rc As SQLITE_C_INT = sqlite3OsOpen(original.pVfs, CPtr(Const ZString Ptr, original.zJournal), _
        pRealFile, original.flags, @outFlags)
    If rc = SQLITE_OK Then
        Dim pChunk As MemJournalFileChunk Ptr = original.pFirst
        Dim fileOffset As sqlite3_int64 = 0
        Dim remaining As sqlite3_int64 = original.endpoint.iOffset
        While pChunk <> 0 AndAlso remaining > 0
            Dim writeSize As SQLITE_C_INT = original.nChunkSize
            If remaining < writeSize Then writeSize = CInt(remaining)
            rc = sqlite3OsWrite(pRealFile, @pChunk->zChunk(0), writeSize, fileOffset)
            If rc <> SQLITE_OK Then Exit While
            fileOffset += writeSize
            remaining -= writeSize
            pChunk = pChunk->pNext
        Wend
        If rc = SQLITE_OK AndAlso remaining <> 0 Then rc = SQLITE_CORRUPT
        If rc = SQLITE_OK Then
            memjrnlFreeChunks(original.pFirst)
            Return SQLITE_OK
        End If
    End If

    sqlite3OsClose(pRealFile)
    *pJournal = original
    Return rc
End Function

Private Function memjrnlWrite CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pBuffer As Const Any Ptr, _
    ByVal amount As SQLITE_C_INT, _
    ByVal offset As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse (amount > 0 AndAlso pBuffer = 0) OrElse amount < 0 OrElse offset < 0 Then Return SQLITE_MISUSE
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pFile)
    If pJournal->nChunkSize < 8 Then Return SQLITE_IOERR_WRITE
    If offset > &H7FFFFFFFFFFFFFFF - amount Then Return SQLITE_FULL
    If offset > pJournal->endpoint.iOffset Then Return SQLITE_IOERR_WRITE

    If pJournal->nSpill > 0 AndAlso offset + amount > pJournal->nSpill Then
        Dim rcCreate As SQLITE_C_INT = memjrnlCreateFile(pJournal)
        If rcCreate <> SQLITE_OK Then Return rcCreate
        Return sqlite3OsWrite(CPtr(sqlite3_file Ptr, pJournal), pBuffer, amount, offset)
    End If

    If offset > 0 AndAlso offset <> pJournal->endpoint.iOffset Then
        Dim rcTruncate As SQLITE_C_INT = memjrnlTruncate(pFile, offset)
        If rcTruncate <> SQLITE_OK Then Return rcTruncate
    End If

    Dim pInput As Const UByte Ptr = CPtr(Const UByte Ptr, pBuffer)
    If offset = 0 AndAlso pJournal->pFirst <> 0 AndAlso amount <= pJournal->nChunkSize Then
        memjrnlCopyBytes(@pJournal->pFirst->zChunk(0), pInput, amount)
        Return SQLITE_OK
    End If
    If offset = 0 AndAlso pJournal->pFirst <> 0 Then
        Dim rcTruncate As SQLITE_C_INT = memjrnlTruncate(pFile, 0)
        If rcTruncate <> SQLITE_OK Then Return rcTruncate
    End If

    Dim remaining As SQLITE_C_INT = amount
    While remaining > 0
        Dim pChunk As MemJournalFileChunk Ptr = pJournal->endpoint.pChunk
        Dim chunkOffset As SQLITE_C_INT = CInt(pJournal->endpoint.iOffset Mod pJournal->nChunkSize)
        Dim chunkSpace As SQLITE_C_INT = pJournal->nChunkSize - chunkOffset
        Dim writeSize As SQLITE_C_INT = IIf(remaining < chunkSpace, remaining, chunkSpace)

        If chunkOffset = 0 Then
            Dim allocationSize As sqlite3_uint64 = memjrnlChunkAllocationSize(pJournal->nChunkSize)
            If allocationSize = 0 Then Return SQLITE_FULL
            Dim pNew As MemJournalFileChunk Ptr = CPtr(MemJournalFileChunk Ptr, sqlite3MallocZero(allocationSize))
            If pNew = 0 Then Return SQLITE_IOERR_NOMEM
            If pChunk <> 0 Then
                pChunk->pNext = pNew
            Else
                pJournal->pFirst = pNew
            End If
            pChunk = pNew
            pJournal->endpoint.pChunk = pNew
        ElseIf pChunk = 0 Then
            Return SQLITE_CORRUPT
        End If

        memjrnlCopyBytes(@pChunk->zChunk(0) + chunkOffset, pInput, writeSize)
        pInput += writeSize
        remaining -= writeSize
        pJournal->endpoint.iOffset += writeSize
    Wend
    Return SQLITE_OK
End Function

Private Function memjrnlTruncate CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal size As sqlite3_int64 _
) As SQLITE_C_INT

    If pFile = 0 OrElse size < 0 Then Return SQLITE_MISUSE
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pFile)
    If pJournal->nChunkSize < 8 Then Return SQLITE_IOERR_TRUNCATE
    If size >= pJournal->endpoint.iOffset Then Return SQLITE_OK

    Dim pLast As MemJournalFileChunk Ptr = 0
    If size = 0 Then
        memjrnlFreeChunks(pJournal->pFirst)
        pJournal->pFirst = 0
    Else
        Dim keepCount As sqlite3_int64 = ((size - 1) \ pJournal->nChunkSize) + 1
        pLast = pJournal->pFirst
        For i As sqlite3_int64 = 1 To keepCount - 1
            If pLast = 0 Then Return SQLITE_CORRUPT
            pLast = pLast->pNext
        Next
        If pLast = 0 Then Return SQLITE_CORRUPT
        memjrnlFreeChunks(pLast->pNext)
        pLast->pNext = 0
    End If

    pJournal->endpoint.pChunk = pLast
    pJournal->endpoint.iOffset = size
    pJournal->readpoint.iOffset = 0
    pJournal->readpoint.pChunk = 0
    Return SQLITE_OK
End Function

Private Function memjrnlClose CDecl (ByVal pFile As Any Ptr) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_OK
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pFile)
    memjrnlFreeChunks(pJournal->pFirst)
    pJournal->pFirst = 0
    pJournal->endpoint.pChunk = 0
    pJournal->endpoint.iOffset = 0
    pJournal->readpoint.pChunk = 0
    pJournal->readpoint.iOffset = 0
    Return SQLITE_OK
End Function

Private Function memjrnlSync CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal flags As SQLITE_C_INT _
) As SQLITE_C_INT
    If pFile = 0 Then Return SQLITE_MISUSE
    Return SQLITE_OK
End Function

Private Function memjrnlFileSize CDecl ( _
    ByVal pFile As Any Ptr, _
    ByVal pSize As sqlite3_int64 Ptr _
) As SQLITE_C_INT
    If pFile = 0 OrElse pSize = 0 Then Return SQLITE_MISUSE
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pFile)
    pSize[0] = pJournal->endpoint.iOffset
    Return SQLITE_OK
End Function

/' ------------------------------------------------------------------------- '/
/' Internal journal entry points '/
/' ------------------------------------------------------------------------- '/

Function sqlite3JournalOpen CDecl Alias "sqlite3JournalOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pJournalFile As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal nSpill As SQLITE_C_INT _
) As SQLITE_C_INT Export

    If pJournalFile = 0 Then Return SQLITE_MISUSE
    If pVfs = 0 AndAlso nSpill >= 0 Then Return SQLITE_MISUSE
    If zName = 0 AndAlso nSpill >= 0 AndAlso (flags And SQLITE_OPEN_EXCLUSIVE) = 0 Then Return SQLITE_MISUSE
    Dim rcMethods As SQLITE_C_INT = memjrnlInitializeMethods()
    If rcMethods <> SQLITE_OK Then Return rcMethods

    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pJournalFile)
    Dim pBytes As UByte Ptr = CPtr(UByte Ptr, pJournal)
    For i As Long = 0 To SizeOf(MemJournal) - 1
        pBytes[i] = 0
    Next

    If nSpill = 0 Then
        Dim outFlags As SQLITE_C_INT = 0
        Dim rcOpen As SQLITE_C_INT = sqlite3OsOpen(pVfs, zName, pJournalFile, flags, @outFlags)
        If rcOpen <> SQLITE_OK AndAlso pJournalFile->pMethods <> 0 Then sqlite3OsClose(pJournalFile)
        Return rcOpen
    End If

    Dim chunkSize As SQLITE_C_INT
    If nSpill > 0 Then
        chunkSize = IIf(nSpill < 8, 8, nSpill)
    Else
        chunkSize = MEMJOURNAL_DEFAULT_FILE_CHUNK_SIZE - SizeOf(MemJournalFileChunk) + 8
    End If
    If memjrnlChunkAllocationSize(chunkSize) = 0 Then Return SQLITE_FULL

    pJournal->pMethods = @memJournalMethods
    pJournal->nChunkSize = chunkSize
    pJournal->nSpill = nSpill
    pJournal->flags = flags
    pJournal->pVfs = pVfs
    pJournal->zJournal = CPtr(Any Ptr, zName)
    Return SQLITE_OK
End Function

Function sqlite3JournalSize CDecl Alias "sqlite3JournalSize" (ByVal pVfs As sqlite3_vfs Ptr) As SQLITE_C_INT Export
    If pVfs = 0 Then Return 0
    Return IIf(pVfs->szOsFile > SizeOf(MemJournal), pVfs->szOsFile, SizeOf(MemJournal))
End Function

Function sqlite3JournalCreate CDecl Alias "sqlite3JournalCreate" (ByVal pJournalFile As sqlite3_file Ptr) As SQLITE_C_INT Export
    If pJournalFile = 0 Then Return SQLITE_MISUSE
    If pJournalFile->pMethods <> @memJournalMethods Then Return SQLITE_OK
    Dim pJournal As MemJournal Ptr = CPtr(MemJournal Ptr, pJournalFile)
    If pJournal->nSpill <= 0 Then Return SQLITE_OK
    Return memjrnlCreateFile(pJournal)
End Function

Function sqlite3JournalIsInMemory CDecl Alias "sqlite3JournalIsInMemory" (ByVal pJournalFile As sqlite3_file Ptr) As SQLITE_C_INT Export
    If pJournalFile = 0 Then Return 0
    Return IIf(pJournalFile->pMethods = @memJournalMethods, 1, 0)
End Function

Sub sqlite3MemJournalOpen CDecl Alias "sqlite3MemJournalOpen" (ByVal pJournalFile As sqlite3_file Ptr) Export
    If pJournalFile = 0 Then Exit Sub
    sqlite3JournalOpen(0, 0, pJournalFile, 0, -1)
End Sub

/' end of sqlite3_memjournal.bas '/
