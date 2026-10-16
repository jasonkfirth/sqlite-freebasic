/'
    Project: SQLite FreeBASIC port

    File: sqlite3_memjournal.bi

    Purpose:

        Declare the in-memory journal file interface used by the pager.

    Responsibilities:

        - Expose memory-journal open, size, spill, and state queries.
        - Keep the internal entry points compatible with SQLite's C ABI.

    This file intentionally does NOT contain:

        - File-method implementations or journal record parsing.
        - Pager transaction policy.
'/ 

#ifndef SQLITE3_FB_MEMJOURNAL_BI
#define SQLITE3_FB_MEMJOURNAL_BI

#include once "sqlite3_types.bi"
#include once "sqlite3_vfs.bi"

Declare Function sqlite3JournalOpen CDecl Alias "sqlite3JournalOpen" ( _
    ByVal pVfs As sqlite3_vfs Ptr, _
    ByVal zName As Const ZString Ptr, _
    ByVal pJournal As sqlite3_file Ptr, _
    ByVal flags As SQLITE_C_INT, _
    ByVal nSpill As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Function sqlite3JournalSize CDecl Alias "sqlite3JournalSize" ( _
    ByVal pVfs As sqlite3_vfs Ptr _
) As SQLITE_C_INT
Declare Function sqlite3JournalCreate CDecl Alias "sqlite3JournalCreate" ( _
    ByVal pJournal As sqlite3_file Ptr _
) As SQLITE_C_INT
Declare Function sqlite3JournalIsInMemory CDecl Alias "sqlite3JournalIsInMemory" ( _
    ByVal pJournal As sqlite3_file Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3MemJournalOpen CDecl Alias "sqlite3MemJournalOpen" ( _
    ByVal pJournal As sqlite3_file Ptr _
)

#endif

/' end of sqlite3_memjournal.bi '/
