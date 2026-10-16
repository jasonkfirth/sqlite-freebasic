/'
    Project: SQLite FreeBASIC port

    File: sqlite3_bulk_feature_vdbeapi_scanstatus.bas

    Purpose:

        Implement the optional sqlite3_stmt_scanstatus_v2() query API.

    Responsibilities:

        - Select a scan-status entry by its visible or full index.
        - Return loop, visit, estimate, name, explain, select, parent, and cycle data.
        - Read cycle totals from the selected VDBE or its outermost frame.

    This file intentionally does NOT contain:

        - Scan-status collection or counter-address setup.
        - Runtime validation beyond the API's output and statement pointers.
'/ 

#lang "fb"
#include once "sqlite3_types.bi"
#include once "sqlite3_constants.bi"
#include once "sqlite3_api_constants.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_util_numeric.bi"

#ifdef SQLITE_ENABLE_STMT_SCANSTATUS
Function sqlite3_stmt_scanstatus_v2 CDecl Alias "sqlite3_stmt_scanstatus_v2" ( _
    ByVal pStatement As SqliteVdbe Ptr, _
    ByVal scanIndex As SQLITE_C_INT, _
    ByVal scanStatusOperation As SQLITE_C_INT, _
    ByVal flags As SQLITE_C_INT, _
    ByVal pOutput As Any Ptr _
) As SQLITE_C_INT Export
    If pStatement = 0 OrElse pOutput = 0 Then Return 1
#ifdef SQLITE_ENABLE_API_ARMOR
    If scanStatusOperation < SQLITE_SCANSTAT_NLOOP OrElse _
       scanStatusOperation > SQLITE_SCANSTAT_NCYCLE Then Return 1
#endif

    Dim pOperations As SqliteVdbeOp Ptr = pStatement->aOp
    Dim operationCount As SQLITE_C_INT = pStatement->nOp
    Dim pFrame As SqliteVdbeFrame Ptr = _
        CPtr(SqliteVdbeFrame Ptr, pStatement->pFrame)
    While pFrame <> 0 AndAlso pFrame->pParent <> 0
        pFrame = pFrame->pParent
    Wend
    If pFrame <> 0 Then
        pOperations = pFrame->aOp
        operationCount = pFrame->nOp
    End If

    If scanIndex < 0 Then
        If scanStatusOperation = SQLITE_SCANSTAT_NCYCLE Then
            Dim totalCycles As sqlite3_int64 = 0
            For operationIndex As SQLITE_C_INT = 0 To operationCount - 1
                totalCycles += Cast(sqlite3_int64, pOperations[operationIndex].nCycle)
            Next
            CPtr(sqlite3_int64 Ptr, pOutput)[0] = totalCycles
            Return SQLITE_OK
        End If
        Return 1
    End If

    Dim selectedIndex As SQLITE_C_INT = 0
    Dim pScan As SqliteScanStatus Ptr = 0
    If (flags And SQLITE_SCANSTAT_COMPLEX) <> 0 Then
        selectedIndex = scanIndex
    Else
        While selectedIndex < pStatement->nScan
            If pStatement->aScan = 0 Then Return 1
            pScan = @pStatement->aScan[selectedIndex]
            If pScan->zName <> 0 Then
                scanIndex -= 1
                If scanIndex < 0 Then Exit While
            End If
            selectedIndex += 1
        Wend
    End If

    If selectedIndex < 0 OrElse selectedIndex >= pStatement->nScan OrElse _
       pStatement->aScan = 0 Then Return 1
    pScan = @pStatement->aScan[selectedIndex]

    Select Case scanStatusOperation
    Case SQLITE_SCANSTAT_NLOOP
        Dim loopCount As sqlite3_int64 = -1
        If pScan->addrLoop > 0 AndAlso pOperations <> 0 Then _
            loopCount = Cast(sqlite3_int64, pOperations[pScan->addrLoop].nExec)
        CPtr(sqlite3_int64 Ptr, pOutput)[0] = loopCount

    Case SQLITE_SCANSTAT_NVISIT
        Dim visitCount As sqlite3_int64 = -1
        If pScan->addrVisit > 0 AndAlso pOperations <> 0 Then _
            visitCount = Cast(sqlite3_int64, pOperations[pScan->addrVisit].nExec)
        CPtr(sqlite3_int64 Ptr, pOutput)[0] = visitCount

    Case SQLITE_SCANSTAT_EST
        Dim estimate As Double = 1.0#
        Dim logEstimate As Short = pScan->nEst
        While logEstimate < 100
            logEstimate += 10
            estimate *= 0.5#
        Wend
        CPtr(Double Ptr, pOutput)[0] = _
            estimate * CDbl(sqlite3LogEstToInt(logEstimate))

    Case SQLITE_SCANSTAT_NAME
        CPtr(Const ZString Ptr Ptr, pOutput)[0] = pScan->zName

    Case SQLITE_SCANSTAT_EXPLAIN
        Dim zExplain As Const ZString Ptr = 0
        If pScan->addrExplain > 0 AndAlso pOperations <> 0 Then _
            zExplain = pOperations[pScan->addrExplain].p4.z
        CPtr(Const ZString Ptr Ptr, pOutput)[0] = zExplain

    Case SQLITE_SCANSTAT_SELECTID
        Dim selectId As SQLITE_C_INT = -1
        If pScan->addrExplain > 0 AndAlso pOperations <> 0 Then _
            selectId = pOperations[pScan->addrExplain].p1
        CPtr(SQLITE_C_INT Ptr, pOutput)[0] = selectId

    Case SQLITE_SCANSTAT_PARENTID
        Dim parentId As SQLITE_C_INT = -1
        If pScan->addrExplain > 0 AndAlso pOperations <> 0 Then _
            parentId = pOperations[pScan->addrExplain].p2
        CPtr(SQLITE_C_INT Ptr, pOutput)[0] = parentId

    Case SQLITE_SCANSTAT_NCYCLE
        Dim cycleCount As sqlite3_int64 = 0
        If pScan->aAddrRange(0) = 0 Then
            cycleCount = -1
        Else
            For rangeIndex As SQLITE_C_INT = 0 To 5 Step 2
                Dim firstAddress As SQLITE_C_INT = pScan->aAddrRange(rangeIndex)
                Dim lastAddress As SQLITE_C_INT = pScan->aAddrRange(rangeIndex + 1)
                If firstAddress = 0 Then Exit For

                If firstAddress > 0 Then
                    If pOperations <> 0 Then
                        While firstAddress <= lastAddress
                            cycleCount += Cast(sqlite3_int64, _
                                pOperations[firstAddress].nCycle)
                            firstAddress += 1
                        Wend
                    End If
                ElseIf pOperations <> 0 Then
                    ' 0x40 marks opcodes that contribute VDBE cycle counts.
                    For operationIndex As SQLITE_C_INT = 0 To operationCount - 1
                        If pOperations[operationIndex].p1 <> lastAddress Then Continue For
                        If (sqlite3OpcodeProperty(pOperations[operationIndex].opcode) _
                            And &H40) = 0 Then Continue For
                        cycleCount += Cast(sqlite3_int64, _
                            pOperations[operationIndex].nCycle)
                    Next
                End If
            Next
        End If
        CPtr(sqlite3_int64 Ptr, pOutput)[0] = cycleCount

    Case Else
        Return 1
    End Select

    Return SQLITE_OK
End Function
#endif

/' end of sqlite3_bulk_feature_vdbeapi_scanstatus.bas '/
