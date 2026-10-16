/'
    Project: SQLite FreeBASIC port

    File: sqlite3_parser_semantics.bas

    Purpose:

        Apply Lemon parser reductions for SQL expressions, statements, and
        compound SELECT queries.

    Responsibilities:

        - Preserve SQLITE_INTERRUPT from SELECT reductions as a runtime error.
        - Build literal Expr and ExprList values from Lemon stack entries.
        - Convert unquoted TRUE/FALSE identifier expressions to boolean literals.
        - Preserve empty, singleton, and vector-list IN expression reductions.
        - Lower infix LIKE, GLOB, and MATCH syntax to function expression nodes.
        - Construct WHERE and LIMIT wrappers, compound SELECT chains, and VALUES rows.
        - Generate transaction and savepoint operations from SQL commands.
        - Apply EXPLAIN, conflict-policy, join, and list semantic reductions.
        - Compile the implemented SELECT path and finish its VDBE.

    This file intentionally does NOT contain:

        - Most schema, DML, aggregate, and virtual-table semantic actions.
'/ 

#lang "fb"
#include once "sqlite3_parser_semantics.bi"
#include once "sqlite3_parser_rule_ids.bi"
#include once "sqlite3_vdbe_core.bi"
#include once "sqlite3_pager.bi"
#include once "sqlite3_numeric.bi"
#include once "sqlite3_walker.bi"
#include once "sqlite3_where_types.bi"
#include once "sqlite3_debug_assert.bi"

Private Const PARSER_SRCITEM_NOT_INDEXED As SQLITE_C_UINT = &H0001
Private Const PARSER_SRCITEM_IS_INDEXED_BY As SQLITE_C_UINT = &H0002

Declare Sub sqlite3FinishCoding CDecl Alias "sqlite3FinishCoding" ( _
    ByVal pParse As Any Ptr _
)
Declare Function sqlite3ReadSchema CDecl Alias "sqlite3ReadSchema" ( _
    ByVal pParse As Any Ptr _
) As SQLITE_C_INT
Declare Sub sqlite3BeginTransaction CDecl Alias "sqlite3BeginTransaction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal transactionType As SQLITE_C_INT _
)
Declare Sub sqlite3EndTransaction CDecl Alias "sqlite3EndTransaction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal endType As SQLITE_C_INT _
)
Declare Sub sqlite3Savepoint CDecl Alias "sqlite3Savepoint" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal operation As SQLITE_C_INT, _
    ByVal pName As sqlite3ParserToken Ptr _
)
Declare Function sqlite3JoinType CDecl Alias "sqlite3JoinType" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pFirst As sqlite3ParserToken Ptr, _
    ByVal pSecond As sqlite3ParserToken Ptr, _
    ByVal pThird As sqlite3ParserToken Ptr _
) As SQLITE_C_INT
Declare Function sqlite3Expr CDecl Alias "sqlite3Expr" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal zToken As Const ZString Ptr _
) As SqliteExpr Ptr
Declare Sub sqlite3ExprUnmapAndDelete CDecl Alias "sqlite3ExprUnmapAndDelete" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpr As SqliteExpr Ptr _
)
Declare Function sqlite3ExprListToValues CDecl Alias "sqlite3ExprListToValues" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal elementCount As SQLITE_C_INT, _
    ByVal pList As SqliteExprList Ptr _
) As SqliteSelect Ptr
Declare Sub sqlite3AddReturning CDecl Alias "sqlite3AddReturning" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpressionList As Any Ptr _
)
Declare Function sqlite3IdListAppend CDecl Alias "sqlite3IdListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pIdList As Any Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As Any Ptr
Declare Sub sqlite3Pragma CDecl Alias "sqlite3Pragma" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr, _
    ByVal pValue As sqlite3ParserToken Ptr, _
    ByVal isNegative As SQLITE_C_INT _
)
Declare Sub sqlite3Vacuum CDecl Alias "sqlite3Vacuum" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pInto As SqliteExpr Ptr _
)
Declare Sub sqlite3Reindex CDecl Alias "sqlite3Reindex" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3Analyze CDecl Alias "sqlite3Analyze" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3DropTable CDecl Alias "sqlite3DropTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal isView As SQLITE_C_INT, _
    ByVal ifExists As SQLITE_C_INT _
)
Declare Sub sqlite3DropIndex CDecl Alias "sqlite3DropIndex" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal ifExists As SQLITE_C_INT _
)
#ifndef SQLITE_OMIT_TRIGGER
Declare Sub sqlite3BeginTrigger CDecl Alias "sqlite3BeginTrigger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr, _
    ByVal triggerTime As SQLITE_C_INT, _
    ByVal eventOperation As SQLITE_C_INT, _
    ByVal pEventColumns As SqliteIdList Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pWhen As SqliteExpr Ptr, _
    ByVal isTemporary As SQLITE_C_INT, _
    ByVal ifNotExists As SQLITE_C_INT _
)
Declare Sub sqlite3FinishTrigger CDecl Alias "sqlite3FinishTrigger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSteps As SqliteTriggerStep Ptr, _
    ByVal pSpan As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3DeleteTriggerStep CDecl Alias "sqlite3DeleteTriggerStep" ( _
    ByVal pDb As sqlite3 Ptr, _
    ByVal pSteps As SqliteTriggerStep Ptr _
)
Declare Function sqlite3TriggerUpdateStep CDecl Alias "sqlite3TriggerUpdateStep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pFrom As SqliteSrcList Ptr, _
    ByVal pAssignments As SqliteExprList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal conflictAction As UByte, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
) As SqliteTriggerStep Ptr
Declare Function sqlite3TriggerInsertStep CDecl Alias "sqlite3TriggerInsertStep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pColumns As SqliteIdList Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal conflictAction As UByte, _
    ByVal pUpsert As SqliteUpsert Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
) As SqliteTriggerStep Ptr
Declare Function sqlite3TriggerDeleteStep CDecl Alias "sqlite3TriggerDeleteStep" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
) As SqliteTriggerStep Ptr
Declare Function sqlite3TriggerSelectStep CDecl Alias "sqlite3TriggerSelectStep" ( _
    ByVal db As sqlite3 Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
) As SqliteTriggerStep Ptr
Declare Sub sqlite3DropTrigger CDecl Alias "sqlite3DropTrigger" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal ifExists As SQLITE_C_INT _
)
#endif
#ifndef SQLITE_OMIT_ATTACH
Declare Sub sqlite3Attach CDecl Alias "sqlite3Attach" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pFilename As SqliteExpr Ptr, _
    ByVal pDatabaseName As SqliteExpr Ptr, _
    ByVal pKey As SqliteExpr Ptr _
)
Declare Sub sqlite3Detach CDecl Alias "sqlite3Detach" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pDatabaseName As SqliteExpr Ptr _
)
#endif
#ifndef SQLITE_OMIT_VIRTUALTABLE
Declare Sub sqlite3VtabBeginParse CDecl Alias "sqlite3VtabBeginParse" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pModuleName As sqlite3ParserToken Ptr, _
    ByVal pDatabaseName As sqlite3ParserToken Ptr, _
    ByVal pTableName As sqlite3ParserToken Ptr, _
    ByVal ifNotExists As SQLITE_C_INT _
)
Declare Sub sqlite3VtabFinishParse CDecl Alias "sqlite3VtabFinishParse" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pEndToken As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3VtabArgInit CDecl Alias "sqlite3VtabArgInit" ( _
    ByVal pParse As SqliteParseContext Ptr _
)
Declare Sub sqlite3VtabArgExtend CDecl Alias "sqlite3VtabArgExtend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
)
#endif
#ifndef SQLITE_OMIT_VIEW
Declare Sub sqlite3CreateView CDecl Alias "sqlite3CreateView" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pCreateToken As sqlite3ParserToken Ptr, _
    ByVal pNameToken As sqlite3ParserToken Ptr, _
    ByVal pDatabaseToken As sqlite3ParserToken Ptr, _
    ByVal pColumnList As SqliteExprList Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal isTemporary As SQLITE_C_INT, _
    ByVal ifNotExists As SQLITE_C_INT _
)
#endif
#ifndef SQLITE_OMIT_ALTERTABLE
#ifndef SQLITE_OMIT_VIRTUALTABLE
Declare Sub sqlite3AlterRenameTable CDecl Alias "sqlite3AlterRenameTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pNewName As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterBeginAddColumn CDecl Alias "sqlite3AlterBeginAddColumn" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr _
)
Declare Sub sqlite3AlterFinishAddColumn CDecl Alias "sqlite3AlterFinishAddColumn" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pEndToken As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterDropColumn CDecl Alias "sqlite3AlterDropColumn" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pColumnName As Const sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterRenameColumn CDecl Alias "sqlite3AlterRenameColumn" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pOldName As sqlite3ParserToken Ptr, _
    ByVal pNewName As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterDropConstraint CDecl Alias "sqlite3AlterDropConstraint" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pConstraintName As sqlite3ParserToken Ptr, _
    ByVal pColumnName As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterSetNotNull CDecl Alias "sqlite3AlterSetNotNull" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pColumnName As sqlite3ParserToken Ptr, _
    ByVal pNotToken As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3AlterAddConstraint CDecl Alias "sqlite3AlterAddConstraint" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pConstraintToken As sqlite3ParserToken Ptr, _
    ByVal pConstraintName As sqlite3ParserToken Ptr, _
    ByVal zCheckExpression As Const ZString Ptr, _
    ByVal checkExpressionLength As SQLITE_C_INT, _
    ByVal pExpression As SqliteExpr Ptr _
)
#endif
#endif
#ifndef SQLITE_OMIT_ALTERTABLE
Declare Sub sqlite3RenameTokenRemap CDecl Alias "sqlite3RenameTokenRemap" ( _
    ByVal pParse As Any Ptr, _
    ByVal pTo As Any Ptr, _
    ByVal pFrom As Any Ptr _
)
#endif
Declare Sub sqlite3AddGenerated CDecl Alias "sqlite3AddGenerated" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal pTypeToken As sqlite3ParserToken Ptr _
)
Declare Function sqlite3SrcListAppend CDecl Alias "sqlite3SrcListAppend" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr, _
    ByVal pTable As sqlite3ParserToken Ptr _
) As SqliteSrcList Ptr
Declare Function sqlite3SrcListAppendFromTerm CDecl Alias "sqlite3SrcListAppendFromTerm" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pTable As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr, _
    ByVal pAlias As sqlite3ParserToken Ptr, _
    ByVal pSubquery As SqliteSelect Ptr, _
    ByVal pOnUsing As sqlite3ParserOnOrUsing Ptr _
) As SqliteSrcList Ptr
Declare Sub sqlite3SrcListDelete CDecl Alias "sqlite3SrcListDelete" ( _
    ByVal pDb As sqlite3 Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr _
)
Declare Sub sqlite3SrcListShiftJoinType CDecl Alias "sqlite3SrcListShiftJoinType" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr _
)
Declare Sub sqlite3SrcListIndexedBy CDecl Alias "sqlite3SrcListIndexedBy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pIndexToken As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3SrcListFuncArgs CDecl Alias "sqlite3SrcListFuncArgs" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pArguments As SqliteExprList Ptr _
)
Declare Function sqlite3ExprFunction CDecl Alias "sqlite3ExprFunction" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pArguments As SqliteExprList Ptr, _
    ByVal pFunctionName As Const sqlite3ParserToken Ptr, _
    ByVal distinctMode As SQLITE_C_INT _
) As SqliteExpr Ptr
Declare Sub sqlite3ExprAddFunctionOrderBy CDecl Alias "sqlite3ExprAddFunctionOrderBy" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr _
)
#ifndef SQLITE_OMIT_SUBQUERY
Declare Sub sqlite3PExprAddSelect CDecl Alias "sqlite3PExprAddSelect" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
#endif
#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Sub sqlite3WindowAttach CDecl Alias "sqlite3WindowAttach" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr _
)
Declare Function sqlite3WindowAlloc CDecl Alias "sqlite3WindowAlloc" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal frameType As SQLITE_C_INT, _
    ByVal startType As SQLITE_C_INT, _
    ByVal pStart As SqliteExpr Ptr, _
    ByVal endType As SQLITE_C_INT, _
    ByVal pEnd As SqliteExpr Ptr, _
    ByVal excludeType As UByte _
) As SqliteWalkerWindow Ptr
Declare Function sqlite3WindowAssemble CDecl Alias "sqlite3WindowAssemble" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr, _
    ByVal pPartition As SqliteExprList Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal pBaseName As sqlite3ParserToken Ptr _
) As SqliteWalkerWindow Ptr
Declare Sub sqlite3WindowChain CDecl Alias "sqlite3WindowChain" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pWindow As SqliteWalkerWindow Ptr, _
    ByVal pBase As SqliteWalkerWindow Ptr _
)
#endif
Declare Function sqlite3RenameTokenMap CDecl Alias "sqlite3RenameTokenMap" ( _
    ByVal pParse As Any Ptr, _
    ByVal pTreeElement As Any Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As Any Ptr
#ifndef SQLITE_OMIT_WINDOWFUNC
Declare Sub sqlite3WindowListDelete CDecl Alias "sqlite3WindowListDelete" ( _
    ByVal pDb As sqlite3 Ptr, _
    ByVal pWindowList As Any Ptr _
)
#endif
Declare Sub sqlite3StartTable CDecl Alias "sqlite3StartTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pName As sqlite3ParserToken Ptr, _
    ByVal pDatabase As sqlite3ParserToken Ptr, _
    ByVal isTemporary As SQLITE_C_INT, _
    ByVal isView As SQLITE_C_INT, _
    ByVal isVirtual As SQLITE_C_INT, _
    ByVal ifNotExists As SQLITE_C_INT _
)
Declare Sub sqlite3AddColumn CDecl Alias "sqlite3AddColumn" ( _
    ByVal pParse As Any Ptr, _
    ByVal nameToken As sqlite3ParserToken, _
    ByVal typeToken As sqlite3ParserToken _
)
Declare Sub sqlite3EndTable CDecl Alias "sqlite3EndTable" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pConstraints As sqlite3ParserToken Ptr, _
    ByVal pEndToken As sqlite3ParserToken Ptr, _
    ByVal tableFlags As SQLITE_C_UINT, _
    ByVal pSelect As SqliteSelect Ptr _
)
Declare Function sqlite3_strnicmp CDecl Alias "sqlite3_strnicmp" ( _
    ByVal zLeft As Const ZString Ptr, _
    ByVal zRight As Const ZString Ptr, _
    ByVal nByte As SQLITE_C_INT _
) As SQLITE_C_INT
Declare Sub sqlite3AddNotNull CDecl Alias "sqlite3AddNotNull" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal onError As SQLITE_C_INT _
)
Declare Sub sqlite3AddDefaultValue CDecl Alias "sqlite3AddDefaultValue" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
)
Declare Sub sqlite3AddPrimaryKey CDecl Alias "sqlite3AddPrimaryKey" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pColumns As SqliteExprList Ptr, _
    ByVal onError As SQLITE_C_INT, _
    ByVal autoincrement As SQLITE_C_INT, _
    ByVal sortOrder As SQLITE_C_INT _
)
Declare Sub sqlite3AddCheckConstraint CDecl Alias "sqlite3AddCheckConstraint" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pExpression As SqliteExpr Ptr, _
    ByVal zStart As Const ZString Ptr, _
    ByVal zEnd As Const ZString Ptr _
)
Declare Sub sqlite3AddCollateType CDecl Alias "sqlite3AddCollateType" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pCollationToken As sqlite3ParserToken Ptr _
)
Declare Sub sqlite3DeferForeignKey CDecl Alias "sqlite3DeferForeignKey" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal isDeferred As SQLITE_C_INT _
)
Declare Sub sqlite3CreateForeignKey CDecl Alias "sqlite3CreateForeignKey" ( _
    ByVal pParse As Any Ptr, _
    ByVal pFromColumns As Any Ptr, _
    ByVal pReferencedTable As Any Ptr, _
    ByVal pToColumns As Any Ptr, _
    ByVal actionFlags As SQLITE_C_INT _
)
Declare Sub sqlite3CreateIndex CDecl Alias "sqlite3CreateIndex" ( _
    ByVal arg0 As Any Ptr, ByVal arg1 As Any Ptr, ByVal arg2 As Any Ptr, _
    ByVal arg3 As Any Ptr, ByVal arg4 As Any Ptr, ByVal arg5 As SQLITE_C_INT, _
    ByVal arg6 As Any Ptr, ByVal arg7 As Any Ptr, _
    ByVal arg8 As SQLITE_C_INT, ByVal arg9 As SQLITE_C_INT, _
    ByVal arg10 As UByte _
)
Declare Sub sqlite3ExprListSetSortOrder CDecl Alias "sqlite3ExprListSetSortOrder" ( _
    ByVal pExpressionList As SqliteExprList Ptr, _
    ByVal sortOrder As SQLITE_C_INT, _
    ByVal nullOrder As SQLITE_C_INT _
)
Declare Function sqlite3ExprListAppendVector CDecl Alias "sqlite3ExprListAppendVector" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal pColumns As SqliteIdList Ptr, _
    ByVal pExpression As SqliteExpr Ptr _
) As SqliteExprList Ptr
Declare Sub sqlite3ExprListCheckLength CDecl Alias "sqlite3ExprListCheckLength" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pList As SqliteExprList Ptr, _
    ByVal zContext As Const ZString Ptr _
)
Declare Function sqlite3SrcListAppendList CDecl Alias "sqlite3SrcListAppendList" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTarget As SqliteSrcList Ptr, _
    ByVal pSource As SqliteSrcList Ptr _
) As SqliteSrcList Ptr
Declare Sub sqlite3Update CDecl Alias "sqlite3Update" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pChanges As SqliteExprList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal onError As SQLITE_C_INT, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal pLimit As SqliteExpr Ptr, _
    ByVal pUpsert As SqliteUpsert Ptr _
)
Declare Sub sqlite3DeleteFrom CDecl Alias "sqlite3DeleteFrom" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pOrderBy As SqliteExprList Ptr, _
    ByVal pLimit As SqliteExpr Ptr _
)
Declare Sub sqlite3Insert CDecl Alias "sqlite3Insert" ( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pTableList As SqliteSrcList Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pColumns As SqliteIdList Ptr, _
    ByVal onError As SQLITE_C_INT, _
    ByVal pUpsert As SqliteUpsert Ptr _
)
Declare Function sqlite3UpsertNew CDecl Alias "sqlite3UpsertNew" ( _
    ByVal pDb As sqlite3 Ptr, _
    ByVal pTarget As SqliteExprList Ptr, _
    ByVal pTargetWhere As SqliteExpr Ptr, _
    ByVal pSetList As SqliteExprList Ptr, _
    ByVal pWhere As SqliteExpr Ptr, _
    ByVal pNext As SqliteUpsert Ptr _
) As SqliteUpsert Ptr

Private Function sqlite3ParserActionError( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal resultCode As SQLITE_C_INT _
) As SQLITE_C_INT
    If pParse <> 0 Then
        pParse->rc = resultCode
        ' SQLite's C parser records SQLITE_INTERRUPT on Parse and stops at
        ' the next token; treating it as a Lemon syntax error changes it to
        ' SQLITE_ERROR in the parser driver's fallback diagnostic.
        If resultCode = SQLITE_INTERRUPT Then Return SQLITE_OK
    End If
    Return resultCode
End Function

' Keep the parser-local and connection-wide lookaside disable counts in step.
' Parse reset subtracts the local count from the connection count.
Private Function sqlite3ParserDisableLookaside( _
    ByVal pParse As SqliteParseContext Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pParse->db = 0 Then Return SQLITE_MISUSE
    If pParse->disableLookaside = &HFF OrElse _
       pParse->db->lookaside.bDisable = &HFFFFFFFF Then _
        Return sqlite3ParserActionError(pParse, SQLITE_TOOBIG)

    pParse->disableLookaside += 1
    pParse->db->lookaside.bDisable += 1
    pParse->db->lookaside.sz = 0
    pParse->u1.cr.addrCrTab = 0
    pParse->u1.cr.regRowid = 0
    pParse->u1.cr.regRoot = 0
    pParse->u1.cr.constraintName.z = 0
    pParse->u1.cr.constraintName.n = 0
    pParse->u1.d.pReturning = 0
    Return SQLITE_OK
End Function

Private Function parserAddExprIdListTerm( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pPrior As SqliteExprList Ptr, _
    ByVal pIdToken As sqlite3ParserToken Ptr, _
    ByVal hasCollation As SQLITE_C_INT, _
    ByVal sortOrder As SQLITE_C_INT _
) As SqliteExprList Ptr
    If pParse = 0 OrElse pParse->db = 0 OrElse pIdToken = 0 Then Return pPrior
    Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend(pParse, pPrior, 0)
    If pList = 0 Then Return 0
    If (hasCollation <> 0 OrElse sortOrder <> SQLITE_SO_UNDEFINED) AndAlso _
       pParse->db->init.busy = 0 Then
        sqlite3ErrorMsg(pParse, StrPtr("syntax error after column name ""%.*s"""), _
            pIdToken->n, CPtr(Const ZString Ptr, pIdToken->z))
    End If
    sqlite3ExprListSetName(pParse, pList, pIdToken, 1)
    Return pList
End Function

Private Sub sqlite3ParserDoubleLinkSelect( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr _
)
    If pParse = 0 OrElse pParse->db = 0 OrElse _
       pSelect = 0 OrElse pSelect->pPrior = 0 Then Exit Sub
    Dim pNext As SqliteSelect Ptr = 0
    Dim pLoop As SqliteSelect Ptr = pSelect
    Dim selectCount As SQLITE_C_INT = 1
    While pLoop <> 0
        pLoop->pNext = pNext
        pLoop->selFlags Or= SF_Compound
        pNext = pLoop
        pLoop = CPtr(SqliteSelect Ptr, pLoop->pPrior)
        If pLoop = 0 Then Exit While
        selectCount += 1
        If pLoop->pOrderBy <> 0 OrElse pLoop->pLimit <> 0 Then
            Dim clauseName As Const ZString Ptr = StrPtr("LIMIT")
            If pLoop->pOrderBy <> 0 Then clauseName = StrPtr("ORDER BY")
            sqlite3ErrorMsg(pParse, _
                StrPtr("%s clause should come after %s not before"), _
                clauseName, sqlite3SelectOpName(pNext->op))
            Exit While
        End If
    Wend

    Dim maxSelect As SQLITE_C_INT = _
        pParse->db->aLimit(SQLITE_LIMIT_COMPOUND_SELECT)
    If (pSelect->selFlags And (SF_MultiValue Or SF_Values)) = 0 AndAlso _
       maxSelect > 0 AndAlso selectCount > maxSelect Then
        sqlite3ErrorMsg(pParse, StrPtr("too many terms in compound SELECT"))
    End If
End Sub

Private Function sqlite3ParserAttachWithToSelect( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSelect As SqliteSelect Ptr, _
    ByVal pWith As SqliteWith Ptr _
) As SqliteSelect Ptr
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    If pSelect = 0 Then
        sqlite3WithDelete(pParse->db, pWith)
        Return 0
    End If
    pSelect->pWith = pWith
    sqlite3ParserDoubleLinkSelect(pParse, pSelect)
    Return pSelect
End Function

Private Function sqlite3ParserTokenSetSpan( _
    ByRef target As sqlite3ParserToken, _
    ByRef startToken As sqlite3ParserToken, _
    ByRef endToken As sqlite3ParserToken _
) As SQLITE_C_INT
    target.z = 0
    target.n = 0
    If startToken.z = 0 OrElse endToken.z = 0 Then Return SQLITE_CORRUPT
    Dim zEnd As Const UByte Ptr = CPtr(Const UByte Ptr, endToken.z) + endToken.n
    If zEnd < CPtr(Const UByte Ptr, startToken.z) Then Return SQLITE_CORRUPT
    Dim tokenLength As LongInt = zEnd - CPtr(Const UByte Ptr, startToken.z)
    If tokenLength < 0 OrElse CULngInt(tokenLength) > &HFFFFFFFFULL Then _
        Return SQLITE_TOOBIG
    target.z = startToken.z
    target.n = CULng(tokenLength)
    Return SQLITE_OK
End Function

Private Function sqlite3ParserFunctionNameEquals( _
    ByVal zFunction As Const UByte Ptr, _
    ByVal zExpected As Const ZString Ptr _
) As SQLITE_C_INT
    If zFunction = 0 OrElse zExpected = 0 Then Return 0
    Dim index As Long = 0
    While zExpected[index] <> 0
        Dim valueByte As UByte = zFunction[index]
        If valueByte >= Asc("A") AndAlso valueByte <= Asc("Z") Then _
            valueByte = valueByte + Asc("a") - Asc("A")
        If valueByte <> CByte(zExpected[index]) Then Return 0
        index += 1
    Wend
    Return CInt(zFunction[index] = 0)
End Function

Private Function sqlite3ParserExprInfixFunction( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByRef operatorToken As sqlite3ParserToken, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pPattern As SqliteExpr Ptr, _
    ByVal pEscape As SqliteExpr Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 Then Return 0

    Dim db As sqlite3 Ptr = pParse->db
    Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend( _
        pParse, 0, pPattern)
    If pList = 0 OrElse db->mallocFailed <> 0 Then
        sqlite3ExprDelete(db, pLeft)
        sqlite3ExprDelete(db, pEscape)
        Return 0
    End If

    pList = sqlite3ExprListAppend(pParse, pList, pLeft)
    If pList = 0 OrElse db->mallocFailed <> 0 Then
        sqlite3ExprDelete(db, pEscape)
        Return 0
    End If
    If pEscape <> 0 Then
        pList = sqlite3ExprListAppend(pParse, pList, pEscape)
        If pList = 0 OrElse db->mallocFailed <> 0 Then Return 0
    End If

    Dim isNegated As SQLITE_C_INT = 0
    If (operatorToken.n And CULng(&H80000000ULL)) <> 0 Then isNegated = 1
    operatorToken.n = operatorToken.n And CULng(&H7FFFFFFFULL)
    Dim pFunction As SqliteExpr Ptr = sqlite3ExprAlloc( _
        db, TK_FUNCTION, @operatorToken, 1)
    If pFunction = 0 Then
        sqlite3ExprListDelete(db, pList)
        Return 0
    End If

    ' The parser must retain the original operator offset because later
    ' expression diagnostics report positions relative to this token.
    If operatorToken.z <> 0 AndAlso pParse->zTail <> 0 Then
        Dim tokenOffset As LongInt = _
            CPtr(Const UByte Ptr, operatorToken.z) - _
            CPtr(Const UByte Ptr, pParse->zTail)
        If tokenOffset < -&H7FFFFFFF OrElse tokenOffset > &H7FFFFFFF Then
            sqlite3ExprDelete(db, pFunction)
            sqlite3ExprListDelete(db, pList)
            Return 0
        End If
        pFunction->w.iOfst = CInt(tokenOffset)
    End If

    pFunction->flags = (pFunction->flags And Not EP_Leaf) Or EP_HasFunc
    pFunction->x.pList = pList
    sqlite3ExprSetHeightAndFlags(pParse, pFunction)
    If db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
        sqlite3ExprDelete(db, pFunction)
        Return 0
    End If

    If isNegated <> 0 Then
        pFunction = sqlite3PExpr(pParse, TK_NOT, pFunction, 0)
        If pFunction = 0 Then Return 0
    End If
    pFunction->flags Or= EP_InfixFunc
    Return pFunction
End Function

Private Function sqlite3ParserExprIsNull( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pExpr As SqliteExpr Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 OrElse pExpr = 0 OrElse _
       (opcode <> TK_ISNULL AndAlso opcode <> TK_NOTNULL) Then
        If pParse <> 0 AndAlso pParse->db <> 0 Then _
            sqlite3ExprDelete(pParse->db, pExpr)
        Return 0
    End If

    Dim pValue As SqliteExpr Ptr = pExpr
    While pValue->op = TK_UPLUS OrElse pValue->op = TK_UMINUS
        If pValue->pLeft = 0 Then
            sqlite3ExprDelete(pParse->db, pExpr)
            Return 0
        End If
        pValue = CPtr(SqliteExpr Ptr, pValue->pLeft)
    Wend
    Select Case pValue->op
    Case TK_INTEGER, TK_STRING, TK_FLOAT, TK_BLOB
        sqlite3ExprDelete(pParse->db, pExpr)
        Return sqlite3ExprInt32( _
            pParse->db, IIf(opcode = TK_NOTNULL, 1, 0))
    End Select
    Return sqlite3PExpr(pParse, opcode, pExpr, 0)
End Function

Private Function sqlite3ParserExprIs( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pLeft As SqliteExpr Ptr, _
    ByVal pRight As SqliteExpr Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 Then Return 0
    If pRight <> 0 AndAlso pRight->op = TK_NULL Then
        sqlite3ExprDelete(pParse->db, pRight)
        If opcode = TK_IS Then
            Return sqlite3ParserExprIsNull(pParse, TK_ISNULL, pLeft)
        End If
        Return sqlite3ParserExprIsNull(pParse, TK_NOTNULL, pLeft)
    End If
    Return sqlite3PExpr(pParse, opcode, pLeft, pRight)
End Function

Private Function parserTokenErrorOffset( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As SQLITE_C_INT
    If pParse = 0 OrElse pToken = 0 OrElse _
       pParse->zTail = 0 OrElse pToken->z = 0 Then Return 0
    Dim tokenAddress As sqlite3_int64 = _
        CLngInt(CULngInt(CPtr(Any Ptr, pToken->z)))
    Dim tailAddress As sqlite3_int64 = _
        CLngInt(CULngInt(CPtr(Any Ptr, pParse->zTail)))
    Return Cast(SQLITE_C_INT, tokenAddress - tailAddress)
End Function

Private Function parserTokenInteriorSpan( _
    ByVal pStartToken As sqlite3ParserToken Ptr, _
    ByVal pEndToken As sqlite3ParserToken Ptr, _
    ByRef zInterior As Const ZString Ptr, _
    ByRef nInterior As SQLITE_C_INT _
) As SQLITE_C_INT
    zInterior = 0
    nInterior = 0
    If pStartToken = 0 OrElse pEndToken = 0 OrElse _
       pStartToken->z = 0 OrElse pEndToken->z = 0 Then Return SQLITE_CORRUPT

    Dim startAddress As sqlite3_uint64 = _
        CULngInt(CPtr(Any Ptr, pStartToken->z))
    Dim endAddress As sqlite3_uint64 = _
        CULngInt(CPtr(Any Ptr, pEndToken->z))
    If endAddress <= startAddress Then Return SQLITE_CORRUPT
    Dim contentLength As sqlite3_uint64 = endAddress - startAddress - 1
    If contentLength > &H7FFFFFFF Then Return SQLITE_TOOBIG

    zInterior = CPtr(Const ZString Ptr, pStartToken->z + 1)
    nInterior = CInt(contentLength)
    Return SQLITE_OK
End Function

Private Function parserTokenExpr( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal opcode As SQLITE_C_INT, _
    ByVal pToken As sqlite3ParserToken Ptr _
) As SqliteExpr Ptr
    If pParse = 0 OrElse pParse->db = 0 OrElse pToken = 0 Then Return 0
    Dim pExpression As SqliteExpr Ptr = sqlite3ExprAlloc( _
        pParse->db, opcode, pToken, 1)
    If pExpression = 0 Then Return 0
    sqlite3ExprSetErrorOffset( _
        pExpression, parserTokenErrorOffset(pParse, pToken))
#ifndef SQLITE_OMIT_ALTERTABLE
    If pParse->eParseMode >= PARSE_MODE_RENAME Then _
        sqlite3RenameTokenMap(pParse, pExpression, pToken)
#endif
    Return pExpression
End Function

Private Sub parserMapSrcListName( _
    ByVal pParse As SqliteParseContext Ptr, _
    ByVal pSourceList As SqliteSrcList Ptr, _
    ByVal pToken As sqlite3ParserToken Ptr _
)
#ifndef SQLITE_OMIT_ALTERTABLE
    If pParse <> 0 AndAlso pSourceList <> 0 AndAlso pToken <> 0 AndAlso _
       pParse->eParseMode >= PARSE_MODE_RENAME Then
        sqlite3RenameTokenMap(pParse, pSourceList->a(0).zName, pToken)
    End If
#endif
End Sub

Function sqlite3ParserSemanticReduce CDecl Alias "sqlite3ParserSemanticReduce" ( _
    ByVal pParser As sqlite3ParserState Ptr, _
    ByVal ruleNumber As SQLITE_C_INT, _
    ByVal rhsCount As SQLITE_C_INT, _
    ByVal lookahead As sqlite3ParserToken, _
    ByVal pResult As sqlite3ParserMinor Ptr _
) As SQLITE_C_INT Export

    If pParser = 0 OrElse pParser->pParse = 0 OrElse pParser->yytos = 0 OrElse _
       pResult = 0 OrElse rhsCount < 0 Then Return SQLITE_MISUSE
    Dim pParse As SqliteParseContext Ptr = CPtr(SqliteParseContext Ptr, pParser->pParse)
    Dim pTop As sqlite3ParserStackEntry Ptr = pParser->yytos
    Dim pResultBytes As UByte Ptr = CPtr(UByte Ptr, pResult)
    Dim tokenEndAddress As sqlite3_uint64
    Dim tokenStartAddress As sqlite3_uint64
    For iByte As Long = 0 To SizeOf(sqlite3ParserMinor) - 1
        pResultBytes[iByte] = 0
    Next

    Select Case ruleNumber
    Case YYRULE_ID_0, YYRULE_ID_1
        Dim expectedRhsCount As SQLITE_C_INT = _
            IIf(ruleNumber = YYRULE_ID_0, 1, 3)
        If rhsCount <> expectedRhsCount Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        If pParse->pReprepare = 0 Then _
            pParse->explain = IIf(ruleNumber = YYRULE_ID_0, 1, 2)

    Case YYRULE_ID_31
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = lookahead

    Case YYRULE_CMDX_CMD
        sqlite3FinishCoding(pParse)

    Case YYRULE_CMD_BEGIN_TRANSTYPE_TRANS_OPT
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3BeginTransaction(pParse, pTop[-1].minor.yy144)

    Case YYRULE_TRANSTYPE_EMPTY
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = TK_DEFERRED

    Case YYRULE_TRANSTYPE_DEFERRED, YYRULE_TRANSTYPE_IMMEDIATE, _
         YYRULE_TRANSTYPE_EXCLUSIVE
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->major

    Case YYRULE_CMD_COMMIT_END_TRANS_OPT, YYRULE_CMD_ROLLBACK_TRANS_OPT
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3EndTransaction(pParse, pTop[-1].major)

    Case YYRULE_CMD_SAVEPOINT_NM
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Savepoint(pParse, SAVEPOINT_BEGIN, @pTop->minor.yy0)

    Case YYRULE_CMD_RELEASE_SAVEPOINT_OPT_NM
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Savepoint(pParse, SAVEPOINT_RELEASE, @pTop->minor.yy0)

    Case YYRULE_CMD_ROLLBACK_TRANS_OPT_TO_SAVEPOINT_OPT_NM
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Savepoint(pParse, SAVEPOINT_ROLLBACK, @pTop->minor.yy0)

    Case YYRULE_ID_75
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Default

    Case YYRULE_ID_76
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->minor.yy144

    Case YYRULE_ID_80
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_ID_81
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_89, YYRULE_ID_91
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->major

    Case YYRULE_ID_116
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.z = 0
        pResult->yy0.n = 0

    Case YYRULE_ID_117
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop->minor.yy0

    Case YYRULE_ID_103
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pStar As SqliteExpr Ptr = sqlite3ExprAlloc( _
            pParse->db, TK_ASTERISK, 0, 0)
        sqlite3ExprSetErrorOffset( _
            pStar, parserTokenErrorOffset(pParse, @pTop->minor.yy0))
        pResult->yy14 = sqlite3ExprListAppend( _
            pParse, CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14), pStar)

    Case YYRULE_ID_104
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pRightStar As SqliteExpr Ptr = _
            sqlite3PExpr(pParse, TK_ASTERISK, 0, 0)
        sqlite3ExprSetErrorOffset( _
            pRightStar, parserTokenErrorOffset(pParse, @pTop->minor.yy0))
        Dim pLeftName As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop[-2].minor.yy0)
        Dim pQualifiedStar As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_DOT, pLeftName, pRightStar)
        pResult->yy14 = sqlite3ExprListAppend( _
            pParse, CPtr(SqliteExprList Ptr, pTop[-4].minor.yy14), _
            pQualifiedStar)

    Case YYRULE_ID_118, YYRULE_ID_120
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop->minor.yy0, 0)
        parserMapSrcListName(pParse, pSourceList, @pTop->minor.yy0)
        pResult->yy203 = pSourceList

    Case YYRULE_ID_119, YYRULE_ID_121
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop[-2].minor.yy0, @pTop->minor.yy0)
        parserMapSrcListName(pParse, pSourceList, @pTop->minor.yy0)
        pResult->yy203 = pSourceList

    Case YYRULE_ID_122
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop[-2].minor.yy0, 0)
        If pSourceList <> 0 Then
#ifndef SQLITE_OMIT_ALTERTABLE
            If pParse->eParseMode >= PARSE_MODE_RENAME Then
                parserMapSrcListName( _
                    pParse, pSourceList, @pTop[-2].minor.yy0)
            Else
                pSourceList->a(0).zAlias = sqlite3NameFromToken( _
                    pParse->db, @pTop->minor.yy0)
            End If
#else
            pSourceList->a(0).zAlias = sqlite3NameFromToken( _
                pParse->db, @pTop->minor.yy0)
#endif
        End If
        pResult->yy203 = pSourceList

    Case YYRULE_ID_123
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop[-4].minor.yy0, @pTop[-2].minor.yy0)
        If pSourceList <> 0 Then
#ifndef SQLITE_OMIT_ALTERTABLE
            If pParse->eParseMode >= PARSE_MODE_RENAME Then
                parserMapSrcListName( _
                    pParse, pSourceList, @pTop[-2].minor.yy0)
            Else
                pSourceList->a(0).zAlias = sqlite3NameFromToken( _
                    pParse->db, @pTop->minor.yy0)
            End If
#else
            pSourceList->a(0).zAlias = sqlite3NameFromToken( _
                pParse->db, @pTop->minor.yy0)
#endif
        End If
        pResult->yy203 = pSourceList

    Case YYRULE_ID_108
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFromList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop->minor.yy203)
        sqlite3SrcListShiftJoinType(pParse, pFromList)
        pResult->yy203 = pFromList

    Case YYRULE_ID_109
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pPrefixList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-1].minor.yy203)
        If pPrefixList <> 0 AndAlso pPrefixList->nSrc > 0 Then
            pPrefixList->a(pPrefixList->nSrc - 1).fg.jointype = _
                CByte(pTop->minor.yy144)
        End If
        pResult->yy203 = pPrefixList

    Case YYRULE_ID_110
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy203 = 0

    Case YYRULE_ID_111
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy203 = sqlite3SrcListAppendFromTerm( _
            pParse, CPtr(SqliteSrcList Ptr, pTop[-4].minor.yy203), _
            @pTop[-3].minor.yy0, @pTop[-2].minor.yy0, _
            @pTop[-1].minor.yy0, 0, @pTop->minor.yy269)

    Case YYRULE_ID_112
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFromList As SqliteSrcList Ptr = sqlite3SrcListAppendFromTerm( _
            pParse, CPtr(SqliteSrcList Ptr, pTop[-5].minor.yy203), _
            @pTop[-4].minor.yy0, @pTop[-3].minor.yy0, _
            @pTop[-2].minor.yy0, 0, @pTop->minor.yy269)
        sqlite3SrcListIndexedBy(pParse, pFromList, @pTop[-1].minor.yy0)
        pResult->yy203 = pFromList

    Case YYRULE_ID_113
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFromList As SqliteSrcList Ptr = sqlite3SrcListAppendFromTerm( _
            pParse, CPtr(SqliteSrcList Ptr, pTop[-7].minor.yy203), _
            @pTop[-6].minor.yy0, @pTop[-5].minor.yy0, _
            @pTop[-1].minor.yy0, 0, @pTop->minor.yy269)
        sqlite3SrcListFuncArgs( _
            pParse, pFromList, CPtr(SqliteExprList Ptr, pTop[-3].minor.yy14))
        pResult->yy203 = pFromList

    Case YYRULE_ID_114
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy203 = sqlite3SrcListAppendFromTerm( _
            pParse, CPtr(SqliteSrcList Ptr, pTop[-5].minor.yy203), _
            0, 0, @pTop[-1].minor.yy0, _
            CPtr(SqliteSelect Ptr, pTop[-3].minor.yy555), _
            @pTop->minor.yy269)

    Case YYRULE_ID_115
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)

        Dim pOuterList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-5].minor.yy203)
        Dim pInnerList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        Dim pAliasToken As sqlite3ParserToken Ptr = @pTop[-1].minor.yy0
        Dim pOnUsing As sqlite3ParserOnOrUsing Ptr = @pTop->minor.yy269

        If pOuterList = 0 AndAlso pAliasToken->n = 0 AndAlso _
           pOnUsing->pOn = 0 AndAlso pOnUsing->pUsing = 0 Then
            pResult->yy203 = pInnerList
        ElseIf pInnerList <> 0 AndAlso pInnerList->nSrc = 1 Then
            Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppendFromTerm( _
                pParse, pOuterList, 0, 0, pAliasToken, 0, pOnUsing)
            If pSourceList <> 0 AndAlso pSourceList->nSrc > 0 Then
                Dim pNew As SqliteSrcItem Ptr = _
                    @pSourceList->a(pSourceList->nSrc - 1)
                Dim pOld As SqliteSrcItem Ptr = @pInnerList->a(0)

#ifdef SQLITE_DEBUG
                If (pOld->fg.flags And SRCITEM_FIXED_SCHEMA) <> 0 Then _
                    sqlite3DebugAssert(StrPtr("pOld->fg.fixedSchema==0"))
#endif
                pNew->zName = pOld->zName
                pOld->zName = 0

                If (pOld->fg.flags And SRCITEM_IS_SUBQUERY) <> 0 Then
                    pNew->fg.flags = pNew->fg.flags Or SRCITEM_IS_SUBQUERY
                    pNew->u4.pSubq = pOld->u4.pSubq
                    pOld->u4.pSubq = 0
                    pOld->fg.flags = pOld->fg.flags And Not SRCITEM_IS_SUBQUERY

#ifdef SQLITE_DEBUG
                    If pNew->u4.pSubq = 0 OrElse _
                       pNew->u4.pSubq->pSelect = 0 Then _
                        sqlite3DebugAssert(StrPtr( _
                            "pNew->u4.pSubq!=0 && pNew->u4.pSubq->pSelect!=0"))
#endif
                    If pNew->u4.pSubq <> 0 AndAlso _
                       pNew->u4.pSubq->pSelect <> 0 AndAlso _
                       (pNew->u4.pSubq->pSelect->selFlags And SF_NestedFrom) <> 0 Then
                        pNew->fg.flags = pNew->fg.flags Or SRCITEM_IS_NESTED_FROM
                    End If
                Else
                    pNew->u4.zDatabase = pOld->u4.zDatabase
                    pOld->u4.zDatabase = 0
                End If

                If (pOld->fg.flags And SRCITEM_IS_TABFUNC) <> 0 Then
                    pNew->u1.pFuncArg = pOld->u1.pFuncArg
                    pOld->u1.pFuncArg = 0
                    pOld->fg.flags = pOld->fg.flags And Not SRCITEM_IS_TABFUNC
                    pNew->fg.flags = pNew->fg.flags Or SRCITEM_IS_TABFUNC
                ElseIf (pOld->fg.flags And PARSER_SRCITEM_IS_INDEXED_BY) <> 0 Then
                    pNew->u1.zIndexedBy = pOld->u1.zIndexedBy
                    pOld->u1.zIndexedBy = 0
                    pOld->fg.flags = pOld->fg.flags And Not PARSER_SRCITEM_IS_INDEXED_BY
                    pNew->fg.flags = pNew->fg.flags Or PARSER_SRCITEM_IS_INDEXED_BY
                End If
                If (pOld->fg.flags And PARSER_SRCITEM_NOT_INDEXED) <> 0 Then _
                    pNew->fg.flags = pNew->fg.flags Or PARSER_SRCITEM_NOT_INDEXED
            End If

            ' Ownership of the moved fields now belongs to the appended item.
            sqlite3SrcListDelete(pParse->db, pInnerList)
            pResult->yy203 = pSourceList
        Else
            sqlite3SrcListShiftJoinType(pParse, pInnerList)
            Dim pNestedSelect As SqliteSelect Ptr = sqlite3SelectNew( _
                pParse, 0, pInnerList, 0, 0, 0, 0, SF_NestedFrom, 0)
            pResult->yy203 = sqlite3SrcListAppendFromTerm( _
                pParse, pOuterList, 0, 0, pAliasToken, pNestedSelect, pOnUsing)
        End If

    Case YYRULE_ID_124
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = JT_INNER

    Case YYRULE_ID_125
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = sqlite3JoinType( _
            pParse, @pTop[-1].minor.yy0, 0, 0)

    Case YYRULE_ID_126
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = sqlite3JoinType( _
            pParse, @pTop[-2].minor.yy0, @pTop[-1].minor.yy0, 0)

    Case YYRULE_ID_127
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = sqlite3JoinType( _
            pParse, @pTop[-3].minor.yy0, @pTop[-2].minor.yy0, _
            @pTop[-1].minor.yy0)

    Case YYRULE_ID_128
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy269.pOn = pTop->minor.yy454
        pResult->yy269.pUsing = 0

    Case YYRULE_ID_129
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy269.pOn = 0
        pResult->yy269.pUsing = pTop[-1].minor.yy14

    Case YYRULE_ID_130
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy269.pOn = 0
        pResult->yy269.pUsing = 0

    Case YYRULE_ID_131
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.z = 0
        pResult->yy0.n = 0

    Case YYRULE_ID_132
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop->minor.yy0

    Case YYRULE_ID_133
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.z = 0
        pResult->yy0.n = 1

    Case YYRULE_ID_155
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = 0

    Case YYRULE_ID_156
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_ID_157
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddReturning(pParse, pTop->minor.yy14)
        pResult->yy454 = 0

    Case YYRULE_ID_158
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddReturning(pParse, pTop->minor.yy14)
        pResult->yy454 = pTop[-2].minor.yy454

    Case YYRULE_ID_152
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pDeleteSources As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-2].minor.yy203)
        Dim pDeleteWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        sqlite3SrcListIndexedBy(pParse, pDeleteSources, @pTop[-1].minor.yy0)
        pTop[-2].minor.yy203 = 0
        pTop->minor.yy454 = 0
        sqlite3DeleteFrom(pParse, pDeleteSources, pDeleteWhere, 0, 0)

    Case YYRULE_ID_159
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pUpdateSources As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-5].minor.yy203)
        Dim pFromSources As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-1].minor.yy203)
        Dim pChangeList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pWhereExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)

        sqlite3SrcListIndexedBy(pParse, pUpdateSources, @pTop[-4].minor.yy0)
        sqlite3ExprListCheckLength(pParse, pChangeList, StrPtr("set list"))
        If pFromSources <> 0 Then
            If pFromSources->nSrc > 1 Then
                Dim pFromSelect As SqliteSelect Ptr = sqlite3SelectNew( _
                    pParse, 0, pFromSources, 0, 0, 0, 0, SF_NestedFrom, 0)
                pTop[-1].minor.yy203 = 0
                Dim emptyAlias As sqlite3ParserToken
                emptyAlias.z = 0
                emptyAlias.n = 0
                pFromSources = sqlite3SrcListAppendFromTerm( _
                    pParse, 0, 0, 0, @emptyAlias, pFromSelect, 0)
            End If
            pUpdateSources = sqlite3SrcListAppendList( _
                pParse, pUpdateSources, pFromSources)
            pTop[-5].minor.yy203 = 0
            pTop[-1].minor.yy203 = 0
        End If

        pTop[-2].minor.yy14 = 0
        pTop->minor.yy454 = 0
        pTop[-5].minor.yy203 = 0
        sqlite3Update( _
            pParse, pUpdateSources, pChangeList, pWhereExpr, _
            pTop[-6].minor.yy144, 0, 0, 0)

    Case YYRULE_ID_160
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSetList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-4].minor.yy14)
        Dim pValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop[-4].minor.yy14 = 0
        pTop->minor.yy454 = 0
        pSetList = sqlite3ExprListAppend(pParse, pSetList, pValue)
        sqlite3ExprListSetName(pParse, pSetList, @pTop[-2].minor.yy0, 1)
        pResult->yy14 = pSetList

    Case YYRULE_ID_161
        If rhsCount <> 7 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSetList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-6].minor.yy14)
        Dim pColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-3].minor.yy132)
        Dim pValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop[-6].minor.yy14 = 0
        pTop[-3].minor.yy132 = 0
        pTop->minor.yy454 = 0
        pResult->yy14 = sqlite3ExprListAppendVector( _
            pParse, pSetList, pColumns, pValue)

    Case YYRULE_ID_162
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSetValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pSetList As SqliteExprList Ptr = sqlite3ExprListAppend( _
            pParse, 0, pSetValue)
        sqlite3ExprListSetName(pParse, pSetList, @pTop[-2].minor.yy0, 1)
        pResult->yy14 = pSetList

    Case YYRULE_ID_163
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-3].minor.yy132)
        Dim pSetValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop[-3].minor.yy132 = 0
        pTop->minor.yy454 = 0
        pResult->yy14 = sqlite3ExprListAppendVector( _
            pParse, 0, pColumns, pSetValue)

    Case YYRULE_ID_164
        If rhsCount <> 7 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pInsertTarget As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        Dim pInsertColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-2].minor.yy132)
        Dim pInsertSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-1].minor.yy555)
        Dim pInsertUpsert As SqliteUpsert Ptr = _
            CPtr(SqliteUpsert Ptr, pTop->minor.yy122)
        Dim insertConflictMode As SQLITE_C_INT = pTop[-5].minor.yy144
        pTop[-3].minor.yy203 = 0
        pTop[-2].minor.yy132 = 0
        pTop[-1].minor.yy555 = 0
        pTop->minor.yy122 = 0
        sqlite3Insert( _
            pParse, pInsertTarget, pInsertSelect, pInsertColumns, _
            insertConflictMode, pInsertUpsert)

    Case YYRULE_ID_165
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pInsertTarget As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-4].minor.yy203)
        Dim pInsertColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-3].minor.yy132)
        Dim insertConflictMode As SQLITE_C_INT = pTop[-6].minor.yy144
        pTop[-4].minor.yy203 = 0
        pTop[-3].minor.yy132 = 0
        sqlite3Insert( _
            pParse, pInsertTarget, 0, pInsertColumns, insertConflictMode, 0)

    Case YYRULE_ID_166
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy122 = 0

    Case YYRULE_ID_167
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pReturningList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop->minor.yy14)
        pTop->minor.yy14 = 0
        sqlite3AddReturning(pParse, pReturningList)
        pResult->yy122 = 0

    Case YYRULE_ID_168
        If rhsCount <> 12 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pUpsertTarget As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-8].minor.yy14)
        Dim pUpsertTargetWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-6].minor.yy454)
        Dim pUpsertSet As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pUpsertWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim pNextUpsert As SqliteUpsert Ptr = _
            CPtr(SqliteUpsert Ptr, pTop->minor.yy122)
        pTop[-8].minor.yy14 = 0
        pTop[-6].minor.yy454 = 0
        pTop[-2].minor.yy14 = 0
        pTop[-1].minor.yy454 = 0
        pTop->minor.yy122 = 0
        pResult->yy122 = sqlite3UpsertNew( _
            pParse->db, pUpsertTarget, pUpsertTargetWhere, _
            pUpsertSet, pUpsertWhere, pNextUpsert)

    Case YYRULE_ID_169
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pUpsertTarget As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-5].minor.yy14)
        Dim pUpsertTargetWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-3].minor.yy454)
        Dim pNextUpsert As SqliteUpsert Ptr = _
            CPtr(SqliteUpsert Ptr, pTop->minor.yy122)
        pTop[-5].minor.yy14 = 0
        pTop[-3].minor.yy454 = 0
        pTop->minor.yy122 = 0
        pResult->yy122 = sqlite3UpsertNew( _
            pParse->db, pUpsertTarget, pUpsertTargetWhere, 0, 0, pNextUpsert)

    Case YYRULE_ID_170
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy122 = sqlite3UpsertNew(pParse->db, 0, 0, 0, 0, 0)

    Case YYRULE_ID_171
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pUpsertSet As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pUpsertWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        pTop[-2].minor.yy14 = 0
        pTop[-1].minor.yy454 = 0
        pResult->yy122 = sqlite3UpsertNew( _
            pParse->db, 0, 0, pUpsertSet, pUpsertWhere, 0)

    Case YYRULE_ID_172
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pReturningList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop->minor.yy14)
        pTop->minor.yy14 = 0
        sqlite3AddReturning(pParse, pReturningList)

    Case YYRULE_ID_173
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->minor.yy144

    Case YYRULE_ID_174
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Replace

    Case YYRULE_ID_175
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy132 = 0

    Case YYRULE_ID_176
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy132 = pTop[-1].minor.yy132

    Case YYRULE_ID_177
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy132 = sqlite3IdListAppend( _
            pParse, pTop[-2].minor.yy132, @pTop->minor.yy0)

    Case YYRULE_ID_178
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy132 = sqlite3IdListAppend( _
            pParse, 0, @pTop->minor.yy0)

    Case YYRULE_ID_181
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pQualifier As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop[-2].minor.yy0)
        Dim pColumn As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop->minor.yy0)
        Dim pQualifiedColumn As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_DOT, pQualifier, pColumn)
        If pQualifiedColumn = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pQualifiedColumn

    Case YYRULE_ID_182
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pDatabase As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop[-4].minor.yy0)
        Dim pTable As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop[-2].minor.yy0)
        Dim pColumn As SqliteExpr Ptr = parserTokenExpr( _
            pParse, TK_ID, @pTop->minor.yy0)
        Dim pTableColumn As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_DOT, pTable, pColumn)
#ifndef SQLITE_OMIT_ALTERTABLE
        If pParse->eParseMode >= PARSE_MODE_RENAME Then _
            sqlite3RenameTokenRemap(pParse, 0, pDatabase)
#endif
        Dim pQualifiedColumn As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_DOT, pDatabase, pTableColumn)
        If pQualifiedColumn = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pQualifiedColumn

    Case YYRULE_ID_190
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pArguments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-4].minor.yy14)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-1].minor.yy14)
        pTop[-4].minor.yy14 = 0
        pTop[-1].minor.yy14 = 0
        Dim pFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, pArguments, @pTop[-7].minor.yy0, _
            pTop[-5].minor.yy144)
        sqlite3ExprAddFunctionOrderBy(pParse, pFunction, pOrderBy)
        pResult->yy454 = pFunction

    Case YYRULE_ID_191
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = sqlite3ExprFunction( _
            pParse, 0, @pTop[-3].minor.yy0, 0)

#ifndef SQLITE_OMIT_WINDOWFUNC
    Case YYRULE_ID_192
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pArguments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-2].minor.yy14 = 0
        pTop->minor.yy211 = 0
        Dim pFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, pArguments, @pTop[-5].minor.yy0, _
            pTop[-3].minor.yy144)
        sqlite3WindowAttach(pParse, pFunction, pWindow)
        pResult->yy454 = pFunction

    Case YYRULE_ID_193
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pArguments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-5].minor.yy14)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-5].minor.yy14 = 0
        pTop[-2].minor.yy14 = 0
        pTop->minor.yy211 = 0
        Dim pFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, pArguments, @pTop[-8].minor.yy0, _
            pTop[-6].minor.yy144)
        sqlite3WindowAttach(pParse, pFunction, pWindow)
        sqlite3ExprAddFunctionOrderBy(pParse, pFunction, pOrderBy)
        pResult->yy454 = pFunction

    Case YYRULE_ID_194
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop->minor.yy211 = 0
        Dim pFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, 0, @pTop[-4].minor.yy0, 0)
        sqlite3WindowAttach(pParse, pFunction, pWindow)
        pResult->yy454 = pFunction
#endif

    Case YYRULE_ID_237
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = 0

    Case YYRULE_ID_238
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = pTop[-1].minor.yy14

    Case YYRULE_ID_239
        If rhsCount <> 12 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pIndexTableList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop[-4].minor.yy0, 0)
        Dim pIndexColumns As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pPartialIndexWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop[-2].minor.yy14 = 0
        pTop->minor.yy454 = 0
        sqlite3CreateIndex( _
            pParse, @pTop[-7].minor.yy0, @pTop[-6].minor.yy0, _
            pIndexTableList, pIndexColumns, pTop[-10].minor.yy144, _
            @pTop[-11].minor.yy0, pPartialIndexWhere, SQLITE_SO_ASC, _
            pTop[-8].minor.yy144, SQLITE_IDXTYPE_APPDEF)
#ifndef SQLITE_OMIT_ALTERTABLE
        If pParse->eParseMode >= PARSE_MODE_RENAME AndAlso _
           pParse->pNewIndex <> 0 Then
            Dim pNewIndex As SqliteIndex Ptr = _
                CPtr(SqliteIndex Ptr, pParse->pNewIndex)
            sqlite3RenameTokenMap( _
                pParse, pNewIndex->zName, @pTop[-4].minor.yy0)
        End If
#endif

    Case YYRULE_ID_195
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pTimeFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, 0, @pTop->minor.yy0, 0)
        If pTimeFunction = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pTimeFunction

    Case YYRULE_ID_196
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pVectorList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-3].minor.yy14)
        Dim pLastValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        pTop[-3].minor.yy14 = 0
        pTop[-1].minor.yy454 = 0
        pVectorList = sqlite3ExprListAppend(pParse, pVectorList, pLastValue)
        If pVectorList = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)

        Dim pVector As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_VECTOR, 0, 0)
        If pVector = 0 Then
            sqlite3ExprListDelete(pParse->db, pVectorList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pVector->x.pList = pVectorList
        For itemIndex As SQLITE_C_INT = 0 To pVectorList->nExpr - 1
            Dim pItemExpr As SqliteExpr Ptr = pVectorList->a(itemIndex).pExpr
            If pItemExpr = 0 Then
                sqlite3ExprDelete(pParse->db, pVector)
                Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
            End If
            pVector->flags = pVector->flags Or _
                (pItemExpr->flags And EP_Propagate)
        Next
        pResult->yy454 = pVector

    Case YYRULE_ID_217
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pLeftValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454)
        Dim pRightValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        Dim operatorToken As sqlite3ParserToken = pTop[-1].minor.yy0
        pTop[-2].minor.yy454 = 0
        pTop->minor.yy454 = 0
        Dim pPointerArgs As SqliteExprList Ptr = sqlite3ExprListAppend( _
            pParse, 0, pLeftValue)
        If pPointerArgs = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pPointerArgs = sqlite3ExprListAppend(pParse, pPointerArgs, pRightValue)
        If pPointerArgs = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        Dim pPointerExpr As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, pPointerArgs, @operatorToken, 0)
        If pPointerExpr = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pPointerExpr

#ifndef SQLITE_OMIT_SUBQUERY
    Case YYRULE_ID_224
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pScalarSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-1].minor.yy555)
        pTop[-1].minor.yy555 = 0
        Dim pScalarExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_SELECT, 0, 0)
        sqlite3PExprAddSelect(pParse, pScalarExpr, pScalarSelect)
        If pScalarExpr = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pScalarExpr

    Case YYRULE_ID_225
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pInLeft As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-4].minor.yy454)
        Dim pInSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-1].minor.yy555)
        Dim negateIn As SQLITE_C_INT = pTop[-3].minor.yy144
        pTop[-4].minor.yy454 = 0
        pTop[-1].minor.yy555 = 0
        Dim pInExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_IN, pInLeft, 0)
        sqlite3PExprAddSelect(pParse, pInExpr, pInSelect)
        If negateIn <> 0 Then pInExpr = sqlite3PExpr(pParse, TK_NOT, pInExpr, 0)
        If pInExpr = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pInExpr

    Case YYRULE_ID_226
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pLeftExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-4].minor.yy454)
        Dim pSourceList As SqliteSrcList Ptr = sqlite3SrcListAppend( _
            pParse, 0, @pTop[-2].minor.yy0, @pTop[-1].minor.yy0)
        Dim pSelect As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, 0, pSourceList, 0, 0, 0, 0, 0, 0)
        Dim pArguments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop->minor.yy14)
        If pArguments <> 0 Then
            pTop->minor.yy14 = 0
            Dim pFunctionSource As SqliteSrcList Ptr = 0
            If pSelect <> 0 Then pFunctionSource = pSourceList
            sqlite3SrcListFuncArgs(pParse, pFunctionSource, pArguments)
        End If
        pTop[-4].minor.yy454 = 0
        Dim pInExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_IN, pLeftExpr, 0)
        sqlite3PExprAddSelect(pParse, pInExpr, pSelect)
        If pTop[-3].minor.yy144 <> 0 Then _
            pInExpr = sqlite3PExpr(pParse, TK_NOT, pInExpr, 0)
        pResult->yy454 = pInExpr

    Case YYRULE_ID_227
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pExistsSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-1].minor.yy555)
        pTop[-1].minor.yy555 = 0
        Dim pExistsExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_EXISTS, 0, 0)
        sqlite3PExprAddSelect(pParse, pExistsExpr, pExistsSelect)
        If pExistsExpr = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExistsExpr
#endif

    Case YYRULE_ID_240
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Abort

    Case YYRULE_ID_241
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_None

    Case YYRULE_ID_249
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Vacuum(pParse, 0, CPtr(SqliteExpr Ptr, pTop->minor.yy454))

    Case YYRULE_ID_250
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Vacuum( _
            pParse, @pTop[-1].minor.yy0, _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454))

    Case YYRULE_ID_251
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_ID_252
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = 0

    Case YYRULE_ID_253
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Pragma( _
            pParse, @pTop[-1].minor.yy0, @pTop->minor.yy0, 0, 0)

    Case YYRULE_ID_254
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Pragma( _
            pParse, @pTop[-3].minor.yy0, @pTop[-2].minor.yy0, _
            @pTop->minor.yy0, 0)

    Case YYRULE_ID_255
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Pragma( _
            pParse, @pTop[-4].minor.yy0, @pTop[-3].minor.yy0, _
            @pTop[-1].minor.yy0, 0)

    Case YYRULE_ID_256
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Pragma( _
            pParse, @pTop[-3].minor.yy0, @pTop[-2].minor.yy0, _
            @pTop->minor.yy0, 1)

    Case YYRULE_ID_257
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Pragma( _
            pParse, @pTop[-4].minor.yy0, @pTop[-3].minor.yy0, _
            @pTop[-1].minor.yy0, 1)

    Case YYRULE_ID_258, YYRULE_ID_259
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop->minor.yy0

    Case YYRULE_ID_262
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->major

    Case YYRULE_ID_263
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = TK_INSTEAD

    Case YYRULE_ID_264
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = TK_BEFORE

    Case YYRULE_ID_265, YYRULE_ID_266
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy286.a = pTop->major
        pResult->yy286.b = 0

    Case YYRULE_ID_267
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy286.a = TK_UPDATE
        pResult->yy286.b = pTop->minor.yy14

    Case YYRULE_ID_268
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = 0

    Case YYRULE_ID_269
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_ID_272
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3ErrorMsg(pParse, StrPtr( _
            "the INDEXED BY clause is not allowed on UPDATE or DELETE statements within triggers"))

    Case YYRULE_ID_273
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3ErrorMsg(pParse, StrPtr( _
            "the NOT INDEXED clause is not allowed on UPDATE or DELETE statements within triggers"))

    Case YYRULE_ID_286
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = 0

    Case YYRULE_ID_287
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_ID_288
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Reindex(pParse, 0, 0)

    Case YYRULE_ID_289
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Reindex(pParse, @pTop[-1].minor.yy0, @pTop->minor.yy0)

    Case YYRULE_ID_290
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Analyze(pParse, 0, 0)

    Case YYRULE_ID_291
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3Analyze(pParse, @pTop[-1].minor.yy0, @pTop->minor.yy0)

#ifndef SQLITE_OMIT_ALTERTABLE
#ifndef SQLITE_OMIT_VIRTUALTABLE
    Case YYRULE_ID_292
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        pTop[-3].minor.yy203 = 0
        sqlite3AlterRenameTable(pParse, pAlterTable, @pTop->minor.yy0)

    Case YYRULE_ID_293
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim endToken As sqlite3ParserToken = pTop[-1].minor.yy0
        If endToken.z = 0 OrElse pParse->sLastToken.z = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim startAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, endToken.z))
        Dim endAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, pParse->sLastToken.z))
        If endAddress < startAddress Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim spanLength As sqlite3_uint64 = _
            endAddress - startAddress + CULngInt(pParse->sLastToken.n)
        If spanLength > &HFFFFFFFFULL Then _
            Return sqlite3ParserActionError(pParse, SQLITE_TOOBIG)
        endToken.n = Cast(u32, spanLength)
        sqlite3AlterFinishAddColumn(pParse, @endToken)

    Case YYRULE_ID_294
        If rhsCount <> 7 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim lookasideCode As SQLITE_C_INT = _
            sqlite3ParserDisableLookaside(pParse)
        If lookasideCode <> SQLITE_OK Then Return lookasideCode
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-4].minor.yy203)
        Dim nameToken As sqlite3ParserToken = pTop[-1].minor.yy0
        Dim typeToken As sqlite3ParserToken = pTop->minor.yy0
        pTop[-4].minor.yy203 = 0
        sqlite3AlterBeginAddColumn(pParse, pAlterTable)
        sqlite3AddColumn(pParse, nameToken, typeToken)
        pResult->yy0 = nameToken

    Case YYRULE_ID_295
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        pTop[-3].minor.yy203 = 0
        sqlite3AlterDropColumn(pParse, pAlterTable, @pTop->minor.yy0)

    Case YYRULE_ID_296
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-5].minor.yy203)
        pTop[-5].minor.yy203 = 0
        sqlite3AlterRenameColumn( _
            pParse, pAlterTable, @pTop[-2].minor.yy0, @pTop->minor.yy0)

    Case YYRULE_ID_297
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        pTop[-3].minor.yy203 = 0
        sqlite3AlterDropConstraint( _
            pParse, pAlterTable, @pTop->minor.yy0, 0)

    Case YYRULE_ID_298
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-6].minor.yy203)
        pTop[-6].minor.yy203 = 0
        sqlite3AlterDropConstraint( _
            pParse, pAlterTable, 0, @pTop[-3].minor.yy0)

    Case YYRULE_ID_299
        If rhsCount <> 10 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-7].minor.yy203)
        pTop[-7].minor.yy203 = 0
        sqlite3AlterSetNotNull( _
            pParse, pAlterTable, @pTop[-4].minor.yy0, @pTop[-2].minor.yy0)

    Case YYRULE_ID_300
        If rhsCount <> 11 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-8].minor.yy203)
        Dim pCheckExpression As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454)
        Dim zCheck As Const ZString Ptr
        Dim nCheck As SQLITE_C_INT = 0
        Dim spanCode As SQLITE_C_INT = parserTokenInteriorSpan( _
            @pTop[-3].minor.yy0, @pTop[-1].minor.yy0, zCheck, nCheck)
        If spanCode <> SQLITE_OK Then _
            Return sqlite3ParserActionError(pParse, spanCode)
        pTop[-8].minor.yy203 = 0
        pTop[-2].minor.yy454 = 0
        sqlite3AlterAddConstraint( _
            pParse, pAlterTable, @pTop[-6].minor.yy0, _
            @pTop[-5].minor.yy0, zCheck, nCheck, pCheckExpression)

    Case YYRULE_ID_301
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pAlterTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-6].minor.yy203)
        Dim pCheckExpression As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454)
        Dim zCheck As Const ZString Ptr
        Dim nCheck As SQLITE_C_INT = 0
        Dim spanCode As SQLITE_C_INT = parserTokenInteriorSpan( _
            @pTop[-3].minor.yy0, @pTop[-1].minor.yy0, zCheck, nCheck)
        If spanCode <> SQLITE_OK Then _
            Return sqlite3ParserActionError(pParse, spanCode)
        pTop[-6].minor.yy203 = 0
        pTop[-2].minor.yy454 = 0
        sqlite3AlterAddConstraint( _
            pParse, pAlterTable, @pTop[-4].minor.yy0, 0, _
            zCheck, nCheck, pCheckExpression)
#endif
#endif

#ifndef SQLITE_OMIT_VIRTUALTABLE
    Case YYRULE_ID_302
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3VtabFinishParse(pParse, 0)

    Case YYRULE_ID_303
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3VtabFinishParse(pParse, @pTop->minor.yy0)

    Case YYRULE_ID_304
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3VtabBeginParse( _
            pParse, @pTop[-3].minor.yy0, @pTop[-2].minor.yy0, _
            @pTop->minor.yy0, pTop[-4].minor.yy144)

    Case YYRULE_ID_305
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3VtabArgInit(pParse)

    Case YYRULE_ID_306, YYRULE_ID_307, YYRULE_ID_308
        If (ruleNumber = YYRULE_ID_307 AndAlso rhsCount <> 3) OrElse _
           (ruleNumber <> YYRULE_ID_307 AndAlso rhsCount <> 1) Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3VtabArgExtend(pParse, @pTop->minor.yy0)
#endif

    Case YYRULE_ID_45
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddGenerated( _
            pParse, CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454), 0)

    Case YYRULE_ID_46
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddGenerated( _
            pParse, CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454), _
            @pTop->minor.yy0)

    Case YYRULE_ID_135
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = pTop->minor.yy14

    Case YYRULE_ID_145
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = pTop->minor.yy14

    Case YYRULE_ID_147
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

#ifndef SQLITE_OMIT_WINDOWFUNC
    Case YYRULE_ID_93
        If rhsCount <> 10 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSelectWithWindows As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, pTop[-7].minor.yy14, pTop[-6].minor.yy203, _
            pTop[-5].minor.yy454, pTop[-4].minor.yy14, _
            pTop[-3].minor.yy454, pTop[-1].minor.yy14, _
            pTop[-8].minor.yy144, pTop->minor.yy454)
        If pSelectWithWindows <> 0 Then
            pSelectWithWindows->pWinDefn = pTop[-2].minor.yy211
        Else
            sqlite3WindowListDelete(pParse->db, pTop[-2].minor.yy211)
        End If
        pResult->yy555 = pSelectWithWindows
#endif

    Case YYRULE_ID_13
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3StartTable(pParse, @pTop[-1].minor.yy0, @pTop->minor.yy0, _
            pTop[-4].minor.yy144, 0, 0, pTop[-2].minor.yy144)

    Case YYRULE_ID_14
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        ' Lemon's A label copies CREATE into the createkw result token.
        pResult->yy0 = pTop->minor.yy0
        ' CREATE schema objects must outlive this parser and can be shared
        ' across connections, so allocate them outside this connection's pool.
        Dim lookasideCode As SQLITE_C_INT = _
            sqlite3ParserDisableLookaside(pParse)
        If lookasideCode <> SQLITE_OK Then Return lookasideCode

    Case YYRULE_ID_15, YYRULE_ID_18
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_16
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_ID_17
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        ' Lemon stores C boolean results as 0 or 1. FreeBASIC equality is -1
        ' when true, so normalize this flag before it reaches sqlite3StartTable.
        If pParse->db->init.busy = 0 Then
            pResult->yy144 = 1
        Else
            pResult->yy144 = 0
        End If

    Case YYRULE_ID_19
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3EndTable(pParse, @pTop[-2].minor.yy0, @pTop[-1].minor.yy0, _
            pTop->minor.yy391, 0)

    Case YYRULE_ID_20
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pCreateSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pTop->minor.yy555)
        sqlite3EndTable(pParse, 0, 0, 0, pCreateSelect)
        sqlite3SelectDelete(pParse->db, pCreateSelect)

    Case YYRULE_ID_21
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy391 = 0

    Case YYRULE_ID_22
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy391 = pTop[-2].minor.yy391 Or pTop->minor.yy391

    Case YYRULE_ID_23
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        If pTop->minor.yy0.n = 5 AndAlso sqlite3_strnicmp( _
            CPtr(Const ZString Ptr, pTop->minor.yy0.z), StrPtr("rowid"), 5) = 0 Then
            pResult->yy391 = TF_WithoutRowid Or TF_NoVisibleRowid
        Else
            pResult->yy391 = 0
            sqlite3ErrorMsg(pParse, StrPtr("unknown table option: %.*s"), _
                pTop->minor.yy0.n, CPtr(Const ZString Ptr, pTop->minor.yy0.z))
        End If

    Case YYRULE_ID_24
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        If pTop->minor.yy0.n = 6 AndAlso sqlite3_strnicmp( _
            CPtr(Const ZString Ptr, pTop->minor.yy0.z), StrPtr("strict"), 6) = 0 Then
            pResult->yy391 = TF_Strict
        Else
            pResult->yy391 = 0
            sqlite3ErrorMsg(pParse, StrPtr("unknown table option: %.*s"), _
                pTop->minor.yy0.n, CPtr(Const ZString Ptr, pTop->minor.yy0.z))
        End If

    Case YYRULE_ID_25
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddColumn(pParse, pTop[-1].minor.yy0, pTop->minor.yy0)

    Case YYRULE_ID_26, YYRULE_ID_65, YYRULE_ID_106
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.z = 0
        pResult->yy0.n = 0

    Case YYRULE_ID_27
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop[-3].minor.yy0
        tokenEndAddress = _
            CULngInt(CPtr(Any Ptr, pTop->minor.yy0.z)) + pTop->minor.yy0.n
        tokenStartAddress = CULngInt(CPtr(Any Ptr, pResult->yy0.z))
        If tokenEndAddress < tokenStartAddress Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.n = CUInt(tokenEndAddress - tokenStartAddress)

    Case YYRULE_ID_28
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop[-5].minor.yy0
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop->minor.yy0.z)) + _
            pTop->minor.yy0.n
        tokenStartAddress = CULngInt(CPtr(Any Ptr, pResult->yy0.z))
        If tokenEndAddress < tokenStartAddress Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.n = CUInt(tokenEndAddress - tokenStartAddress)

    Case YYRULE_ID_29
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop[-1].minor.yy0
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop->minor.yy0.z)) + _
            pTop->minor.yy0.n
        tokenStartAddress = CULngInt(CPtr(Any Ptr, pResult->yy0.z))
        If tokenEndAddress < tokenStartAddress Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0.n = CUInt(tokenEndAddress - tokenStartAddress)

    Case YYRULE_ID_32, YYRULE_ID_67
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pParse->u1.cr.constraintName = pTop->minor.yy0

    Case YYRULE_ID_33
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop[-1].minor.yy0.z)) + _
            pTop[-1].minor.yy0.n
        sqlite3AddDefaultValue(pParse, CPtr(SqliteExpr Ptr, pTop->minor.yy454), _
            CPtr(Const ZString Ptr, pTop[-1].minor.yy0.z), _
            CPtr(Const ZString Ptr, CPtr(Any Ptr, tokenEndAddress)))

    Case YYRULE_ID_34
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddDefaultValue(pParse, CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454), _
            CPtr(Const ZString Ptr, CPtr(Const UByte Ptr, pTop[-2].minor.yy0.z) + 1), _
            CPtr(Const ZString Ptr, pTop->minor.yy0.z))

    Case YYRULE_ID_35
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop[-1].minor.yy0.z)) + _
            pTop[-1].minor.yy0.n
        sqlite3AddDefaultValue(pParse, CPtr(SqliteExpr Ptr, pTop->minor.yy454), _
            CPtr(Const ZString Ptr, pTop[-2].minor.yy0.z), _
            CPtr(Const ZString Ptr, CPtr(Any Ptr, tokenEndAddress)))

    Case YYRULE_ID_36
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop[-1].minor.yy0.z)) + _
            pTop[-1].minor.yy0.n
        Dim pNegativeDefault As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_UMINUS, CPtr(SqliteExpr Ptr, pTop->minor.yy454), 0)
        sqlite3AddDefaultValue(pParse, pNegativeDefault, _
            CPtr(Const ZString Ptr, pTop[-2].minor.yy0.z), _
            CPtr(Const ZString Ptr, CPtr(Any Ptr, tokenEndAddress)))

    Case YYRULE_ID_37
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        tokenEndAddress = CULngInt(CPtr(Any Ptr, pTop->minor.yy0.z)) + pTop->minor.yy0.n
        Dim pKeywordDefault As SqliteExpr Ptr = sqlite3ExprAlloc( _
            pParse->db, TK_STRING, @pTop->minor.yy0, 1)
        If pKeywordDefault <> 0 Then sqlite3ExprIdToTrueFalse(pKeywordDefault)
        sqlite3AddDefaultValue(pParse, pKeywordDefault, _
            CPtr(Const ZString Ptr, pTop->minor.yy0.z), _
            CPtr(Const ZString Ptr, CPtr(Any Ptr, tokenEndAddress)))

    Case YYRULE_ID_38
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddNotNull(pParse, pTop->minor.yy144)

    Case YYRULE_ID_39
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddPrimaryKey(pParse, 0, pTop[-1].minor.yy144, _
            pTop->minor.yy144, pTop[-2].minor.yy144)

    Case YYRULE_ID_40
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3CreateIndex(pParse, 0, 0, 0, 0, pTop->minor.yy144, _
            0, 0, 0, 0, SQLITE_IDXTYPE_UNIQUE)

    Case YYRULE_ID_41
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddCheckConstraint(pParse, CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454), _
            CPtr(Const ZString Ptr, pTop[-2].minor.yy0.z), _
            CPtr(Const ZString Ptr, pTop->minor.yy0.z))

    Case YYRULE_ID_42
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3CreateForeignKey(pParse, 0, @pTop[-2].minor.yy0, _
            pTop[-1].minor.yy14, pTop->minor.yy144)

    Case YYRULE_ID_43
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3DeferForeignKey(pParse, pTop->minor.yy144)

    Case YYRULE_ID_44
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddCollateType(pParse, @pTop->minor.yy0)

    Case YYRULE_ID_47
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_48
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_ID_49
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_50
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = (pTop[-1].minor.yy144 And Not pTop->minor.yy383.mask) Or _
            pTop->minor.yy383.value

    Case YYRULE_ID_51, YYRULE_ID_52
        If rhsCount <> 2 AndAlso rhsCount <> 3 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy383.value = 0
        pResult->yy383.mask = 0

    Case YYRULE_ID_53
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy383.value = pTop->minor.yy144
        pResult->yy383.mask = &H0000FF

    Case YYRULE_ID_54
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy383.value = pTop->minor.yy144 Shl 8
        pResult->yy383.mask = &H00FF00

    Case YYRULE_ID_55
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_SetNull

    Case YYRULE_ID_56
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_SetDflt

    Case YYRULE_ID_57
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Cascade

    Case YYRULE_ID_58
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Restrict

    Case YYRULE_ID_59
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_None

    Case YYRULE_ID_60
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_61
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->minor.yy144

    Case YYRULE_ID_62, YYRULE_ID_64, YYRULE_ID_72
        If rhsCount <> 0 AndAlso ruleNumber <> 64 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        If ruleNumber = 64 AndAlso rhsCount <> 2 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_63
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_ID_71
        If rhsCount <> 10 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3CreateForeignKey(pParse, pTop[-6].minor.yy14, _
            @pTop[-3].minor.yy0, pTop[-2].minor.yy14, pTop[-1].minor.yy144)
        sqlite3DeferForeignKey(pParse, pTop->minor.yy144)

    Case YYRULE_ID_73
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Default

    Case YYRULE_ID_74
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->minor.yy144

    Case YYRULE_ID_77
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Ignore

    Case YYRULE_ID_78
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Replace

    Case YYRULE_ID_79
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3DropTable( _
            pParse, CPtr(SqliteSrcList Ptr, pTop->minor.yy203), _
            0, pTop[-1].minor.yy144)

#ifndef SQLITE_OMIT_VIEW
    Case YYRULE_ID_82
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3CreateView( _
            pParse, @pTop[-8].minor.yy0, @pTop[-4].minor.yy0, _
            @pTop[-3].minor.yy0, CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14), _
            CPtr(SqliteSelect Ptr, pTop->minor.yy555), _
            pTop[-7].minor.yy144, pTop[-5].minor.yy144)
#endif

    Case YYRULE_ID_83
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3DropTable( _
            pParse, CPtr(SqliteSrcList Ptr, pTop->minor.yy203), _
            1, pTop[-1].minor.yy144)

    Case YYRULE_ID_280
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Rollback

    Case YYRULE_ID_281
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Abort

    Case YYRULE_ID_282
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = OE_Fail

#ifndef SQLITE_OMIT_TRIGGER
    Case YYRULE_ID_283
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3DropTrigger( _
            pParse, CPtr(SqliteSrcList Ptr, pTop->minor.yy203), _
            pTop[-1].minor.yy144)

    Case YYRULE_ID_260
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim startToken As sqlite3ParserToken = pTop[-3].minor.yy0
        Dim endToken As sqlite3ParserToken = pTop->minor.yy0
        If startToken.z = 0 OrElse endToken.z = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim startAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, startToken.z))
        Dim endAddress As sqlite3_uint64 = _
            CULngInt(CPtr(Any Ptr, endToken.z))
        If endAddress < startAddress Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim spanLength As sqlite3_uint64 = _
            endAddress - startAddress + CULngInt(endToken.n)
        If spanLength > &HFFFFFFFFULL Then _
            Return sqlite3ParserActionError(pParse, SQLITE_TOOBIG)
        Dim pTriggerSteps As SqliteTriggerStep Ptr = _
            CPtr(SqliteTriggerStep Ptr, pTop[-1].minor.yy427)
        Dim spanToken As sqlite3ParserToken
        spanToken.z = startToken.z
        spanToken.n = Cast(u32, spanLength)
        pTop[-1].minor.yy427 = 0
        sqlite3FinishTrigger(pParse, pTriggerSteps, @spanToken)

    Case YYRULE_ID_261
        If rhsCount <> 11 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pTriggerColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-4].minor.yy286.b)
        Dim pTriggerTable As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-2].minor.yy203)
        Dim pWhenExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        Dim nameToken As sqlite3ParserToken = pTop[-7].minor.yy0
        Dim databaseToken As sqlite3ParserToken = pTop[-6].minor.yy0
        sqlite3BeginTrigger( _
            pParse, @nameToken, @databaseToken, pTop[-5].minor.yy144, _
            pTop[-4].minor.yy286.a, pTriggerColumns, pTriggerTable, _
            pWhenExpr, pTop[-10].minor.yy144, pTop[-8].minor.yy144)
        pTop[-4].minor.yy286.b = 0
        pTop[-2].minor.yy203 = 0
        pTop->minor.yy454 = 0
        If databaseToken.n <> 0 Then
            pResult->yy0 = databaseToken
        Else
            pResult->yy0 = nameToken
        End If

    Case YYRULE_ID_270
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSteps As SqliteTriggerStep Ptr = _
            CPtr(SqliteTriggerStep Ptr, pTop[-2].minor.yy427)
        Dim pNewStep As SqliteTriggerStep Ptr = _
            CPtr(SqliteTriggerStep Ptr, pTop[-1].minor.yy427)
        If pSteps = 0 OrElse pSteps->pLast = 0 OrElse pNewStep = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pSteps->pLast->pNext = pNewStep
        pSteps->pLast = pNewStep
        pTop[-2].minor.yy427 = 0
        pTop[-1].minor.yy427 = 0
        pResult->yy427 = pSteps

    Case YYRULE_ID_271
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSteps As SqliteTriggerStep Ptr = _
            CPtr(SqliteTriggerStep Ptr, pTop[-1].minor.yy427)
        If pSteps = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pSteps->pLast = pSteps
        pTop[-1].minor.yy427 = 0
        pResult->yy427 = pSteps

    Case YYRULE_ID_274
        If rhsCount <> 9 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pTableList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-6].minor.yy203)
        Dim pFromList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-2].minor.yy203)
        Dim pAssignments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-3].minor.yy14)
        Dim pWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim zStart As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop[-8].minor.yy0.z)
        Dim zEnd As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop->minor.yy168)
        pTop[-6].minor.yy203 = 0
        pTop[-2].minor.yy203 = 0
        pTop[-3].minor.yy14 = 0
        pTop[-1].minor.yy454 = 0
        pResult->yy427 = sqlite3TriggerUpdateStep( _
            pParse, pTableList, pFromList, pAssignments, pWhere, _
            pTop[-7].minor.yy144, zStart, zEnd)

    Case YYRULE_ID_275
        If rhsCount <> 8 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pTableList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-4].minor.yy203)
        Dim pColumns As SqliteIdList Ptr = _
            CPtr(SqliteIdList Ptr, pTop[-3].minor.yy132)
        Dim pSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-2].minor.yy555)
        Dim pUpsert As SqliteUpsert Ptr = _
            CPtr(SqliteUpsert Ptr, pTop[-1].minor.yy122)
        Dim zStart As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop[-7].minor.yy168)
        Dim zEnd As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop->minor.yy168)
        pTop[-4].minor.yy203 = 0
        pTop[-3].minor.yy132 = 0
        pTop[-2].minor.yy555 = 0
        pTop[-1].minor.yy122 = 0
        pResult->yy427 = sqlite3TriggerInsertStep( _
            pParse, pTableList, pColumns, pSelect, _
            pTop[-6].minor.yy144, pUpsert, zStart, zEnd)

    Case YYRULE_ID_276
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pTableList As SqliteSrcList Ptr = _
            CPtr(SqliteSrcList Ptr, pTop[-3].minor.yy203)
        Dim pWhere As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim zStart As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop[-5].minor.yy0.z)
        Dim zEnd As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop->minor.yy168)
        pTop[-3].minor.yy203 = 0
        pTop[-1].minor.yy454 = 0
        pResult->yy427 = sqlite3TriggerDeleteStep( _
            pParse, pTableList, pWhere, zStart, zEnd)

    Case YYRULE_ID_277
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop[-1].minor.yy555)
        Dim zStart As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop[-2].minor.yy168)
        Dim zEnd As Const ZString Ptr = _
            CPtr(Const ZString Ptr, pTop->minor.yy168)
        pTop[-1].minor.yy555 = 0
        pResult->yy427 = sqlite3TriggerSelectStep( _
            pParse->db, pSelect, zStart, zEnd)

    Case YYRULE_ID_278
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pRaise As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_RAISE, 0, 0)
        If pRaise <> 0 Then pRaise->affExpr = CByte(OE_Ignore)
        pResult->yy454 = pRaise

    Case YYRULE_ID_279
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pErrorExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim raisetype As SQLITE_C_INT = pTop[-3].minor.yy144
        pTop[-1].minor.yy454 = 0
        Dim pRaise As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_RAISE, pErrorExpr, 0)
        If pRaise <> 0 Then pRaise->affExpr = CByte(raisetype)
        pResult->yy454 = pRaise
#endif

#ifndef SQLITE_OMIT_ATTACH
    Case YYRULE_ID_284
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFilenameExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-3].minor.yy454)
        Dim pDatabaseExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim pKeyExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop[-3].minor.yy454 = 0
        pTop[-1].minor.yy454 = 0
        pTop->minor.yy454 = 0
        sqlite3Attach(pParse, pFilenameExpr, pDatabaseExpr, pKeyExpr)

    Case YYRULE_ID_285
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pDatabaseExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        sqlite3Detach(pParse, pDatabaseExpr)
#endif

    Case YYRULE_ID_242
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = 0

    Case YYRULE_ID_243
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = pTop[-1].minor.yy14

    Case YYRULE_ID_244
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = parserAddExprIdListTerm( _
            pParse, pTop[-4].minor.yy14, @pTop[-2].minor.yy0, _
            pTop[-1].minor.yy144, pTop->minor.yy144)

    Case YYRULE_ID_245
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = parserAddExprIdListTerm( _
            pParse, 0, @pTop[-2].minor.yy0, pTop[-1].minor.yy144, _
            pTop->minor.yy144)

    Case YYRULE_ID_138
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_ASC

    Case YYRULE_ID_139
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_DESC

    Case YYRULE_ID_140
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_UNDEFINED

    Case YYRULE_ID_68
        If rhsCount <> 7 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddPrimaryKey(pParse, CPtr(SqliteExprList Ptr, pTop[-3].minor.yy14), _
            pTop->minor.yy144, pTop[-2].minor.yy144, 0)

    Case YYRULE_ID_69
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3CreateIndex(pParse, 0, 0, 0, pTop[-2].minor.yy14, _
            pTop->minor.yy144, 0, 0, 0, 0, SQLITE_IDXTYPE_UNIQUE)

    Case YYRULE_ID_70
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3AddCheckConstraint(pParse, CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454), _
            CPtr(Const ZString Ptr, pTop[-3].minor.yy0.z), _
            CPtr(Const ZString Ptr, pTop[-1].minor.yy0.z))

    Case YYRULE_ID_66
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pParse->u1.cr.constraintName.n = 0

    Case YYRULE_ID_136
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSortList As SqliteExprList Ptr = sqlite3ExprListAppend( _
            pParse, pTop[-4].minor.yy14, CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454))
        sqlite3ExprListSetSortOrder(pSortList, _
            pTop[-1].minor.yy144, pTop->minor.yy144)
        pResult->yy14 = pSortList

    Case YYRULE_ID_137
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pSortList As SqliteExprList Ptr = _
            sqlite3ExprListAppend(pParse, 0, CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454))
        sqlite3ExprListSetSortOrder(pSortList, _
            pTop[-1].minor.yy144, pTop->minor.yy144)
        pResult->yy14 = pSortList

    Case YYRULE_ID_141
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_ASC

    Case YYRULE_ID_142
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_DESC

    Case YYRULE_ID_143
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = SQLITE_SO_UNDEFINED

    Case YYRULE_ID_246
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_ID_247
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_ID_248
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        ' RHS is DROP INDEX ifexists fullname, so the flag is below the name.
        sqlite3DropIndex( _
            pParse, CPtr(SqliteSrcList Ptr, pTop->minor.yy203), _
            pTop[-1].minor.yy144)

#ifndef SQLITE_OMIT_WINDOWFUNC
    Case YYRULE_ID_318
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pWindowList As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop[-2].minor.yy211)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        If pWindow = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        sqlite3WindowChain(pParse, pWindow, pWindowList)
        pWindow->pNextWin = pWindowList
        pTop[-2].minor.yy211 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = pWindow

    Case YYRULE_ID_319
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop[-1].minor.yy211)
        If pWindow <> 0 Then
            pWindow->zName = CPtr(ZString Ptr, sqlite3DbStrNDup( _
                pParse->db, CPtr(Const ZString Ptr, pTop[-4].minor.yy0.z), _
                pTop[-4].minor.yy0.n))
        End If
        pTop[-1].minor.yy211 = 0
        pResult->yy211 = pWindow

    Case YYRULE_ID_320
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pPartition As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-1].minor.yy14)
        Dim pFrame As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-2].minor.yy14 = 0
        pTop[-1].minor.yy14 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = sqlite3WindowAssemble( _
            pParse, pFrame, pPartition, pOrderBy, 0)

    Case YYRULE_ID_321
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pPartition As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-2].minor.yy14)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-1].minor.yy14)
        Dim pFrame As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-2].minor.yy14 = 0
        pTop[-1].minor.yy14 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = sqlite3WindowAssemble( _
            pParse, pFrame, pPartition, pOrderBy, @pTop[-5].minor.yy0)

    Case YYRULE_ID_322
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-1].minor.yy14)
        Dim pFrame As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-1].minor.yy14 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = sqlite3WindowAssemble( _
            pParse, pFrame, 0, pOrderBy, 0)

    Case YYRULE_ID_323
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pTop[-1].minor.yy14)
        Dim pFrame As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop[-1].minor.yy14 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = sqlite3WindowAssemble( _
            pParse, pFrame, 0, pOrderBy, @pTop[-4].minor.yy0)

    Case YYRULE_ID_324
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFrame As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        pTop->minor.yy211 = 0
        pResult->yy211 = sqlite3WindowAssemble( _
            pParse, pFrame, 0, 0, @pTop[-1].minor.yy0)

    Case YYRULE_ID_325
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy211 = sqlite3WindowAlloc( _
            pParse, 0, TK_UNBOUNDED, 0, TK_CURRENT, 0, 0)

    Case YYRULE_ID_326
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim startBound As sqlite3ParserFrameBound = pTop[-1].minor.yy509
        pTop[-1].minor.yy509.pExpr = 0
        pResult->yy211 = sqlite3WindowAlloc( _
            pParse, pTop[-2].minor.yy144, startBound.eType, _
            CPtr(SqliteExpr Ptr, startBound.pExpr), TK_CURRENT, 0, _
            CByte(pTop->minor.yy462))

    Case YYRULE_ID_327
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim startBound As sqlite3ParserFrameBound = pTop[-3].minor.yy509
        Dim endBound As sqlite3ParserFrameBound = pTop[-1].minor.yy509
        pTop[-3].minor.yy509.pExpr = 0
        pTop[-1].minor.yy509.pExpr = 0
        pResult->yy211 = sqlite3WindowAlloc( _
            pParse, pTop[-5].minor.yy144, startBound.eType, _
            CPtr(SqliteExpr Ptr, startBound.pExpr), endBound.eType, _
            CPtr(SqliteExpr Ptr, endBound.pExpr), CByte(pTop->minor.yy462))

    Case YYRULE_ID_328
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = pTop->major

    Case YYRULE_ID_329, YYRULE_ID_331
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy509 = pTop->minor.yy509
        pTop->minor.yy509.pExpr = 0

    Case YYRULE_ID_330, YYRULE_ID_332, YYRULE_ID_334
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy509.eType = pTop[-1].major
        pResult->yy509.pExpr = 0

    Case YYRULE_ID_333
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy509.eType = pTop->major
        pResult->yy509.pExpr = pTop[-1].minor.yy454
        pTop[-1].minor.yy454 = 0

    Case YYRULE_ID_335
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy462 = 0

    Case YYRULE_ID_336
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy462 = pTop->minor.yy462

    Case YYRULE_ID_337, YYRULE_ID_338
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy462 = Cast(u8, pTop[-1].major)

    Case YYRULE_ID_339
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy462 = Cast(u8, pTop->major)

    Case YYRULE_ID_340
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy211 = pTop->minor.yy211
        pTop->minor.yy211 = 0

    Case YYRULE_ID_341
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFilter As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-1].minor.yy454)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop->minor.yy211)
        If pWindow <> 0 Then
            pWindow->pFilter = pFilter
        Else
            sqlite3ExprDelete(pParse->db, pFilter)
        End If
        pTop[-1].minor.yy454 = 0
        pTop->minor.yy211 = 0
        pResult->yy211 = pWindow

    Case YYRULE_ID_342
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy211 = pTop->minor.yy211
        pTop->minor.yy211 = 0

    Case YYRULE_ID_343
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pFilter As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, sqlite3DbMallocZero( _
                pParse->db, CULngInt(SizeOf(SqliteWalkerWindow))))
        If pWindow <> 0 Then
            pWindow->eFrmType = TK_FILTER
            pWindow->pFilter = pFilter
        Else
            sqlite3ExprDelete(pParse->db, pFilter)
        End If
        pResult->yy211 = pWindow

    Case YYRULE_ID_344
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, pTop[-1].minor.yy211)
        If pWindow = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pTop[-1].minor.yy211 = 0
        pResult->yy211 = pWindow

    Case YYRULE_ID_345
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pWindow As SqliteWalkerWindow Ptr = _
            CPtr(SqliteWalkerWindow Ptr, sqlite3DbMallocZero( _
                pParse->db, CULngInt(SizeOf(SqliteWalkerWindow))))
        If pWindow <> 0 Then
            pWindow->zName = CPtr(ZString Ptr, sqlite3DbStrNDup( _
                pParse->db, CPtr(Const ZString Ptr, pTop->minor.yy0.z), _
                pTop->minor.yy0.n))
        End If
        pResult->yy211 = pWindow

    Case YYRULE_ID_346
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop[-1].minor.yy454
        pTop[-1].minor.yy454 = 0
#endif

    Case YYRULE_SCANPT_EMPTY
        pResult->yy168 = lookahead.z

    Case YYRULE_CMD_SELECT
        Dim pSelect As SqliteSelect Ptr = _
            CPtr(SqliteSelect Ptr, pTop->minor.yy555)
        If pSelect = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
        Dim destination As SqliteSelectDest
        destination.eDest = SRT_Output
        destination.iSDParm = 0
        destination.iSDParm2 = 0
        destination.iSdst = 0
        destination.nSdst = 0
        destination.zAffSdst = 0
        destination.pOrderBy = 0
        If (pParse->db->mDbFlags And DBFLAG_EncodingFixed) <> 0 OrElse _
           sqlite3ReadSchema(pParse) = SQLITE_OK Then
            sqlite3Select(pParse, pSelect, @destination)
        End If
        sqlite3SelectDelete(pParse->db, pSelect)

    Case YYRULE_SELECT_WITH, YYRULE_SELECT_WITH_RECURSIVE
        Dim pWith As SqliteWith Ptr = CPtr(SqliteWith Ptr, pTop[-1].minor.yy59)
        Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pTop->minor.yy555)
        pTop[-1].minor.yy59 = 0
        pTop->minor.yy555 = 0
        pResult->yy555 = sqlite3ParserAttachWithToSelect(pParse, pSelect, pWith)

    Case YYRULE_SELECT_SELECTNOWITH
        Dim pSelect As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pTop->minor.yy555)
        sqlite3ParserDoubleLinkSelect(pParse, pSelect)
        pResult->yy555 = pSelect

    Case YYRULE_WITH_WQLIST, YYRULE_WITH_RECURSIVE_WQLIST
        Dim pWith As SqliteWith Ptr = CPtr(SqliteWith Ptr, pTop->minor.yy59)
        If pWith <> 0 Then
            If sqlite3WithPush(pParse, pWith, 1) = 0 Then
                pTop->minor.yy59 = 0
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
            End If
        End If
        pTop->minor.yy59 = 0

    Case YYRULE_WQAS_AS
        pResult->yy462 = M10D_ANY

    Case YYRULE_WQAS_MATERIALIZED
        pResult->yy462 = M10D_YES

    Case YYRULE_WQAS_NOT_MATERIALIZED
        pResult->yy462 = M10D_NO

    Case YYRULE_WQITEM
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 5
        Dim pName As Const sqlite3ParserToken Ptr = @pBase[0].minor.yy0
        Dim pColumns As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[1].minor.yy14)
        Dim materialization As u8 = pBase[2].minor.yy462
        Dim pQuery As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pBase[4].minor.yy555)
        pBase[1].minor.yy14 = 0
        pBase[4].minor.yy555 = 0
        Dim pCte As SqliteCte Ptr = sqlite3CteNew( _
            pParse, pName, pColumns, pQuery, materialization)
        If pCte = 0 Then
            If pParse->db->mallocFailed <> 0 Then _
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
            Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
        End If
        pResult->yy67 = pCte

    Case YYRULE_WITHNM
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pParse->bHasWith = 1
        pResult->yy0 = pTop->minor.yy0

    Case YYRULE_WQLIST_WQITEM
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pCte As SqliteCte Ptr = CPtr(SqliteCte Ptr, pTop->minor.yy67)
        pTop->minor.yy67 = 0
        pResult->yy59 = sqlite3WithAdd(pParse, 0, pCte)

    Case YYRULE_WQLIST_COMMA_WQITEM
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pWith As SqliteWith Ptr = CPtr(SqliteWith Ptr, pBase[0].minor.yy59)
        Dim pCte As SqliteCte Ptr = CPtr(SqliteCte Ptr, pTop->minor.yy67)
        pBase[0].minor.yy59 = 0
        pTop->minor.yy67 = 0
        pResult->yy59 = sqlite3WithAdd(pParse, pWith, pCte)

    Case YYRULE_MULTISELECT_UNION_ALL
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = TK_ALL

    Case YYRULE_SELECTNOWITH_COMPOUND
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pLeft As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pBase[0].minor.yy555)
        Dim pRight As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pBase[2].minor.yy555)
        Dim compoundOpcode As SQLITE_C_INT = pBase[1].minor.yy144
        pBase[0].minor.yy555 = 0
        pBase[2].minor.yy555 = 0

        ' Lemon's grammar permits a compound SELECT on the right. Wrap that
        ' chain as a FROM-subquery before linking it into the outer compound.
        If pRight <> 0 AndAlso pRight->pPrior <> 0 Then
            Dim emptyToken As sqlite3ParserToken
            emptyToken.z = 0
            emptyToken.n = 0
            sqlite3ParserDoubleLinkSelect(pParse, pRight)
            Dim pFrom As SqliteSrcList Ptr = sqlite3SrcListAppendFromTerm( _
                pParse, 0, 0, 0, @emptyToken, pRight, 0)
            pRight = sqlite3SelectNew(pParse, 0, pFrom, 0, 0, 0, 0, 0, 0)
        End If

        If pRight <> 0 Then
            pRight->op = CByte(compoundOpcode)
            pRight->pPrior = pLeft
            If pLeft <> 0 Then pLeft->selFlags And= Not SF_MultiValue
            pRight->selFlags And= Not SF_MultiValue
            If compoundOpcode <> TK_ALL Then pParse->hasCompound = 1
        Else
            sqlite3SelectDelete(pParse->db, pLeft)
        End If
        pResult->yy555 = pRight

    Case YYRULE_ONESELECT
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 8
        Dim pExprList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[2].minor.yy14)
        Dim pSource As Any Ptr = pBase[3].minor.yy203
        Dim pWhere As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[4].minor.yy454)
        Dim pGroupBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[5].minor.yy14)
        Dim pHaving As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[6].minor.yy454)
        Dim pOrderBy As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[7].minor.yy14)
        Dim pLimit As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[8].minor.yy454)
        pBase[2].minor.yy14 = 0
        pBase[3].minor.yy203 = 0
        pBase[4].minor.yy454 = 0
        pBase[5].minor.yy14 = 0
        pBase[6].minor.yy454 = 0
        pBase[7].minor.yy14 = 0
        pBase[8].minor.yy454 = 0
        Dim pSelect As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, _
            pExprList, pSource, pWhere, pGroupBy, pHaving, pOrderBy, _
            CUInt(pBase[1].minor.yy144), _
            pLimit)
        If pSelect = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy555 = pSelect

    Case YYRULE_VALUES_ROW
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 3
        Dim pRow As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[2].minor.yy14)
        pBase[2].minor.yy14 = 0
        Dim pSelect As SqliteSelect Ptr = sqlite3SelectNew( _
            pParse, pRow, 0, 0, 0, 0, 0, SF_Values, 0)
        If pSelect = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy555 = pSelect

    Case YYRULE_ONSELECT_VALUES
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy555 = pTop->minor.yy555

    Case YYRULE_ONSELECT_MVALUES
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        sqlite3MultiValuesEnd(pParse, CPtr(SqliteSelect Ptr, pTop->minor.yy555))
        pResult->yy555 = pTop->minor.yy555

    Case YYRULE_MVALUES_FIRST_ROW, YYRULE_MVALUES_NEXT_ROW
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pLeft As SqliteSelect Ptr = CPtr(SqliteSelect Ptr, pBase[0].minor.yy555)
        Dim pRow As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[3].minor.yy14)
        pBase[0].minor.yy555 = 0
        pBase[3].minor.yy14 = 0
        Dim pSelect As SqliteSelect Ptr = sqlite3MultiValues(pParse, pLeft, pRow)
        If pSelect = 0 Then
            Dim rc As SQLITE_C_INT = IIf( _
                pParse->rc = SQLITE_OK, SQLITE_NOMEM, pParse->rc)
            Return sqlite3ParserActionError(pParse, rc)
        End If
        pResult->yy555 = pSelect

    Case YYRULE_DISTINCT
        pResult->yy144 = SF_Distinct
    Case YYRULE_ALL
        pResult->yy144 = SF_All
    Case YYRULE_DISTINCT_EMPTY
        pResult->yy144 = 0

    Case YYRULE_SCLP_EMPTY
        pResult->yy14 = 0

    Case YYRULE_SELCOLLIST_EXPR
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pPriorList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[0].minor.yy14)
        Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        pBase[0].minor.yy14 = 0
        pBase[2].minor.yy454 = 0
        Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend( _
            pParse, pPriorList, pExpr)
        If pParse->db->mallocFailed <> 0 OrElse pList = 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        If pBase[4].minor.yy0.n > 0 Then _
            sqlite3ExprListSetName(pParse, pList, @pBase[4].minor.yy0, 1)
        sqlite3ExprListSetSpan( _
            pParse, pList, pBase[1].minor.yy168, pBase[3].minor.yy168)
        If pParse->db->mallocFailed <> 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy14 = pList

    Case YYRULE_NEXPRLIST_APPEND
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pPriorList As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[0].minor.yy14)
        Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        pBase[0].minor.yy14 = 0
        pBase[2].minor.yy454 = 0
        Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend( _
            pParse, pPriorList, pExpr)
        If pParse->db->mallocFailed <> 0 OrElse pList = 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy14 = pList

    Case YYRULE_NEXPRLIST_FIRST
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend(pParse, 0, pExpr)
        If pParse->db->mallocFailed <> 0 OrElse pList = 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy14 = pList

    Case YYRULE_AS_NM
        pResult->yy0 = pTop->minor.yy0
    Case YYRULE_AS_EMPTY
        pResult->yy0.z = 0
        pResult->yy0.n = 0

    Case YYRULE_FROM_EMPTY
        pResult->yy203 = 0
    Case YYRULE_ORDERBY_EMPTY, YYRULE_GROUPBY_EMPTY
        pResult->yy14 = 0
    Case YYRULE_HAVING_EMPTY, YYRULE_LIMIT_EMPTY, YYRULE_WHERE_EMPTY, _
         YYRULE_CASE_ELSE_EMPTY, YYRULE_CASE_OPERAND_EMPTY
        pResult->yy454 = 0

    Case YYRULE_CASE_ELSE_EXPR
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_CASE_EXPRLIST_APPEND
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[0].minor.yy14)
        Dim pWhen As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        Dim pThen As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[4].minor.yy454)
        pBase[0].minor.yy14 = 0
        pBase[2].minor.yy454 = 0
        pBase[4].minor.yy454 = 0
        pList = sqlite3ExprListAppend(pParse, pList, pWhen)
        If pList = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprDelete(pParse->db, pThen)
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pList = sqlite3ExprListAppend(pParse, pList, pThen)
        If pList = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy14 = pList

    Case YYRULE_CASE_EXPRLIST_FIRST
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 3
        Dim pWhen As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[1].minor.yy454)
        Dim pThen As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[3].minor.yy454)
        pBase[1].minor.yy454 = 0
        pBase[3].minor.yy454 = 0
        Dim pList As SqliteExprList Ptr = sqlite3ExprListAppend(pParse, 0, pWhen)
        If pList = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprDelete(pParse->db, pThen)
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pList = sqlite3ExprListAppend(pParse, pList, pThen)
        If pList = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy14 = pList

    Case YYRULE_EXPR_CASE
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pOperand As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[1].minor.yy454)
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[2].minor.yy14)
        Dim pElse As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[3].minor.yy454)
        pBase[1].minor.yy454 = 0
        pBase[2].minor.yy14 = 0
        pBase[3].minor.yy454 = 0
        If pElse <> 0 Then
            pList = sqlite3ExprListAppend(pParse, pList, pElse)
            If pList = 0 OrElse pParse->db->mallocFailed <> 0 Then
                sqlite3ExprDelete(pParse->db, pOperand)
                sqlite3ExprListDelete(pParse->db, pList)
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
            End If
        End If
        If pList = 0 Then
            sqlite3ExprDelete(pParse->db, pOperand)
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        End If
        Dim pCase As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_CASE, pOperand, 0)
        If pCase = 0 Then
            sqlite3ExprListDelete(pParse->db, pList)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pCase->x.pList = pList
        sqlite3ExprSetHeightAndFlags(pParse, pCase)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ExprDelete(pParse->db, pCase)
            Dim rc As SQLITE_C_INT = IIf( _
                pParse->db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_ERROR)
            Return sqlite3ParserActionError(pParse, rc)
        End If
        pResult->yy454 = pCase

    Case YYRULE_EXPR_FUNCTION
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim token As sqlite3ParserToken = pBase[0].minor.yy0
        Dim pArguments As SqliteExprList Ptr = _
            CPtr(SqliteExprList Ptr, pBase[3].minor.yy14)
        pBase[3].minor.yy14 = 0
        Dim pFunction As SqliteExpr Ptr = sqlite3ExprFunction( _
            pParse, pArguments, @token, pBase[2].minor.yy144)
        If pFunction = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pFunction

    Case YYRULE_LIKEOP_NOT
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop->minor.yy0
        pResult->yy0.n = pResult->yy0.n Or CULng(&H80000000ULL)

    Case YYRULE_EXPR_LIKE, YYRULE_EXPR_LIKE_ESCAPE
        Dim expectedRhsCount As SQLITE_C_INT = _
            IIf(ruleNumber = YYRULE_EXPR_LIKE, 3, 5)
        If rhsCount <> expectedRhsCount Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - (rhsCount - 1)
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim pPattern As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        Dim pEscape As SqliteExpr Ptr = 0
        If ruleNumber = YYRULE_EXPR_LIKE_ESCAPE Then _
            pEscape = CPtr(SqliteExpr Ptr, pBase[4].minor.yy454)
        pBase[0].minor.yy454 = 0
        pBase[2].minor.yy454 = 0
        If ruleNumber = YYRULE_EXPR_LIKE_ESCAPE Then pBase[4].minor.yy454 = 0
        Dim operatorToken As sqlite3ParserToken = pBase[1].minor.yy0
        Dim pInfix As SqliteExpr Ptr = sqlite3ParserExprInfixFunction( _
            pParse, operatorToken, pLeft, pPattern, pEscape)
        If pInfix = 0 Then
            Dim errorCode As SQLITE_C_INT = SQLITE_ERROR
            If pParse->db->mallocFailed <> 0 Then errorCode = SQLITE_NOMEM
            Return sqlite3ParserActionError(pParse, errorCode)
        End If
        pResult->yy454 = pInfix

    Case YYRULE_IN_OP_IN
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_IN_OP_NOT_IN
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_EXPRLIST_EMPTY
        If rhsCount <> 0 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = 0

    Case YYRULE_EXPR_IN_LIST
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim pList As SqliteExprList Ptr = CPtr(SqliteExprList Ptr, pBase[3].minor.yy14)
        Dim negateResult As SQLITE_C_INT = pBase[1].minor.yy144
        If pList = 0 Then
            ' Empty IN lists become Boolean constants. Keep a function-bearing
            ' left operand in the tree so aggregate classification remains
            ' unchanged, even though the Boolean result is already known.
            Dim zBoolean As Const ZString Ptr
            If negateResult <> 0 Then
                zBoolean = StrPtr("true")
            Else
                zBoolean = StrPtr("false")
            End If
            Dim pBoolean As SqliteExpr Ptr = sqlite3Expr( _
                pParse->db, TK_STRING, zBoolean)
            If pBoolean <> 0 Then sqlite3ExprIdToTrueFalse(pBoolean)
            If pLeft = 0 OrElse (pLeft->flags And EP_HasFunc) = 0 Then
                sqlite3ExprUnmapAndDelete(pParse, pLeft)
                pBase[0].minor.yy454 = 0
                pLeft = pBoolean
            Else
                Dim logicalOpcode As SQLITE_C_INT = _
                    IIf(negateResult <> 0, TK_OR, TK_AND)
                pLeft = sqlite3PExpr(pParse, logicalOpcode, pBoolean, pLeft)
                pBase[0].minor.yy454 = 0
            End If
        Else
            Dim pRight As SqliteExpr Ptr = _
                CPtr(SqliteExpr Ptr, pList->a(0).pExpr)
            If pList->nExpr = 1 AndAlso pRight <> 0 AndAlso _
               sqlite3ExprIsConstant(pParse, pRight) <> 0 AndAlso _
               (pLeft = 0 OrElse pLeft->op <> TK_VECTOR) Then
                ' A one-item constant list is an equality test. The unary plus
                ' prevents index affinity from changing the RHS expression.
                pList->a(0).pExpr = 0
                sqlite3ExprListDelete(pParse->db, pList)
                pRight = sqlite3PExpr(pParse, TK_UPLUS, pRight, 0)
                pLeft = sqlite3PExpr(pParse, TK_EQ, pLeft, pRight)
            ElseIf pList->nExpr = 1 AndAlso pRight <> 0 AndAlso _
                   pRight->op = TK_SELECT Then
                Dim pIn As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_IN, pLeft, 0)
                If pIn <> 0 Then
                    pLeft = pIn
                    sqlite3PExprAddSelect( _
                        pParse, pIn, CPtr(SqliteSelect Ptr, pRight->x.pSelect))
                    pRight->x.pSelect = 0
                    sqlite3ExprListDelete(pParse->db, pList)
                Else
                    sqlite3ExprListDelete(pParse->db, pList)
                    pLeft = 0
                End If
            Else
                Dim pIn As SqliteExpr Ptr = sqlite3PExpr(pParse, TK_IN, pLeft, 0)
                If pIn = 0 Then
                    sqlite3ExprListDelete(pParse->db, pList)
                    pLeft = 0
                ElseIf pIn->pLeft <> 0 AndAlso _
                      pIn->pLeft->op = TK_VECTOR AndAlso _
                      pIn->pLeft->x.pList <> 0 Then
                    pLeft = pIn
                    Dim nElement As SQLITE_C_INT = _
                        CPtr(SqliteExprList Ptr, pIn->pLeft->x.pList)->nExpr
                    Dim pValues As SqliteSelect Ptr = sqlite3ExprListToValues( _
                        pParse, nElement, pList)
                    If pValues <> 0 Then
                        sqlite3ParserDoubleLinkSelect(pParse, pValues)
                        sqlite3PExprAddSelect(pParse, pIn, pValues)
                    End If
                Else
                    pIn->x.pList = pList
                    sqlite3ExprSetHeightAndFlags(pParse, pIn)
                    pLeft = pIn
                End If
            End If

            If negateResult <> 0 Then pLeft = sqlite3PExpr(pParse, TK_NOT, pLeft, 0)
        End If
        pBase[0].minor.yy454 = 0
        pBase[3].minor.yy14 = 0
        pResult->yy454 = pLeft

    Case YYRULE_LIMIT_EXPR
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pLimitValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pLimit As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_LIMIT, pLimitValue, 0)
        If pLimit = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pLimit

    Case YYRULE_LIMIT_OFFSET, YYRULE_LIMIT_COMMA
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 3
        Dim pFirstValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[1].minor.yy454)
        Dim pSecondValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[3].minor.yy454)
        pBase[1].minor.yy454 = 0
        pBase[3].minor.yy454 = 0
        Dim pLimitValue As SqliteExpr Ptr
        Dim pOffsetValue As SqliteExpr Ptr
        If ruleNumber = YYRULE_LIMIT_OFFSET Then
            pLimitValue = pFirstValue
            pOffsetValue = pSecondValue
        Else
            pLimitValue = pSecondValue
            pOffsetValue = pFirstValue
        End If
        Dim pLimit As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_LIMIT, pLimitValue, pOffsetValue)
        If pLimit = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pLimit

    Case YYRULE_WHERE_EXPR
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop->minor.yy454

    Case YYRULE_TYPETOKEN_EMPTY
        pResult->yy0.z = 0
        pResult->yy0.n = 0

    Case YYRULE_TYPETOKEN_TYPENAME, YYRULE_TYPENAME_IDS
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy0 = pTop->minor.yy0

    Case YYRULE_TYPETOKEN_PAREN, YYRULE_TYPETOKEN_PAREN_TWO, _
         YYRULE_TYPENAME_APPEND
        If rhsCount <> 2 AndAlso rhsCount <> 4 AndAlso rhsCount <> 6 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - (rhsCount - 1)
        Dim startToken As sqlite3ParserToken = pBase[0].minor.yy0
        Dim endToken As sqlite3ParserToken = pTop->minor.yy0
        Dim spanCode As SQLITE_C_INT = sqlite3ParserTokenSetSpan( _
            pResult->yy0, startToken, endToken)
        If spanCode <> SQLITE_OK Then Return sqlite3ParserActionError(pParse, spanCode)

    Case YYRULE_CAST_EXPR
        If rhsCount <> 6 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 5
        Dim pOperand As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        Dim typeToken As sqlite3ParserToken = pBase[4].minor.yy0
        pBase[2].minor.yy454 = 0
        Dim pCast As SqliteExpr Ptr = sqlite3ExprAlloc( _
            pParse->db, TK_CAST, @typeToken, 1)
        If pCast = 0 Then
            sqlite3ExprDelete(pParse->db, pOperand)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pCast->flags = pCast->flags And Not EP_Leaf
        pCast->pLeft = pOperand
        sqlite3ExprSetHeightAndFlags(pParse, pCast)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ExprDelete(pParse->db, pCast)
            Dim rc As SQLITE_C_INT = IIf( _
                pParse->db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_ERROR)
            Return sqlite3ParserActionError(pParse, rc)
        End If
        pResult->yy454 = pCast

    Case YYRULE_LIMIT_EXPR
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pLimitValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pLimit As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_LIMIT, pLimitValue, 0)
        If pLimit = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pLimit

    Case YYRULE_LIMIT_OFFSET, YYRULE_LIMIT_COMMA
        If rhsCount <> 4 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 3
        Dim pFirstValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[1].minor.yy454)
        Dim pSecondValue As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[3].minor.yy454)
        pBase[1].minor.yy454 = 0
        pBase[3].minor.yy454 = 0
        Dim pLimitValue As SqliteExpr Ptr
        Dim pOffsetValue As SqliteExpr Ptr
        If ruleNumber = YYRULE_LIMIT_OFFSET Then
            pLimitValue = pFirstValue
            pOffsetValue = pSecondValue
        Else
            pLimitValue = pSecondValue
            pOffsetValue = pFirstValue
        End If
        Dim pLimit As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_LIMIT, pLimitValue, pOffsetValue)
        If pLimit = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pLimit

    Case YYRULE_EXPR_PAREN
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy454 = pTop[-1].minor.yy454

    Case YYRULE_EXPR_COLLATE
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pExpr As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pTop[-2].minor.yy454)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
        Dim pCollationName As sqlite3ParserToken = pTop->minor.yy0
        pTop[-2].minor.yy454 = 0
        Dim pCollated As SqliteExpr Ptr = sqlite3ExprAddCollateToken( _
            pParse, pExpr, @pCollationName, 1)
        If pCollated = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprDelete(pParse->db, pCollated)
            Dim rc As SQLITE_C_INT = IIf( _
                pParse->db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_ERROR)
            Return sqlite3ParserActionError(pParse, rc)
        End If
        pResult->yy454 = pCollated

    Case YYRULE_TERM_NULL_FLOAT_BLOB, YYRULE_TERM_STRING
        Dim token As sqlite3ParserToken = pTop->minor.yy0
        Dim pExpr As SqliteExpr Ptr = _
            parserTokenExpr(pParse, pTop->major, @token)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_TERM_INTEGER
        Dim token As sqlite3ParserToken = pTop->minor.yy0
        Dim integerValue As SQLITE_C_INT = 0
        Dim pExpr As SqliteExpr Ptr
        If sqlite3GetInt32(CPtr(Const ZString Ptr, token.z), @integerValue) = 0 Then
            pExpr = sqlite3ExprAlloc(pParse->db, TK_INTEGER, @token, 0)
        Else
            pExpr = sqlite3ExprInt32(pParse->db, integerValue)
        End If
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_TERM_QNUMBER
        Dim token As sqlite3ParserToken = pTop->minor.yy0
        Dim pExpr As SqliteExpr Ptr = sqlite3ExprAlloc( _
            pParse->db, TK_QNUMBER, @token, 0)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        sqlite3DequoteNumber(pParse, pExpr)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_ID
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim token As sqlite3ParserToken = pTop->minor.yy0
        Dim pExpr As SqliteExpr Ptr = parserTokenExpr(pParse, TK_ID, @token)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        sqlite3ExprIdToTrueFalse(pExpr)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_VARIABLE
        Dim token As sqlite3ParserToken = pTop->minor.yy0
        If token.z = 0 OrElse token.n = 0 Then _
            Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)

        If token.n >= 2 AndAlso token.z[0] = Asc("#") AndAlso _
           token.z[1] >= Asc("0") AndAlso token.z[1] <= Asc("9") Then
            If pParse->nested = 0 Then
                sqlite3ErrorMsg(pParse, StrPtr("near ""%T"": syntax error"), @token)
                Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
            End If

            Dim pRegisterExpr As SqliteExpr Ptr = _
                sqlite3PExpr(pParse, TK_REGISTER, 0, 0)
            If pRegisterExpr = 0 Then _
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)

            Dim registerIndex As SQLITE_C_INT = 0
            If sqlite3GetInt32( _
                CPtr(Const ZString Ptr, token.z + 1), @registerIndex) = 0 OrElse _
               registerIndex <= 0 Then
                sqlite3ExprDelete(pParse->db, pRegisterExpr)
                Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
            End If
            pRegisterExpr->iTable = registerIndex
            pResult->yy454 = pRegisterExpr
        Else
            Dim pVariableExpr As SqliteExpr Ptr = sqlite3ExprAlloc( _
                pParse->db, TK_VARIABLE, @token, 0)
            If pVariableExpr = 0 Then _
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
            Dim rc As SQLITE_C_INT = sqlite3ExprAssignVarNumber( _
                pParse, pVariableExpr, CInt(token.n))
            If rc <> SQLITE_OK Then
                sqlite3ExprDelete(pParse->db, pVariableExpr)
                Return sqlite3ParserActionError(pParse, rc)
            End If
            pResult->yy454 = pVariableExpr
        End If

    Case YYRULE_EXPR_AND
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim pRight As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        pBase[0].minor.yy454 = 0
        pBase[2].minor.yy454 = 0
        Dim pExpr As SqliteExpr Ptr = sqlite3ExprAnd(pParse, pLeft, pRight)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_NULL_TEST
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 1
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim opcode As SQLITE_C_INT = pBase[1].major
        pBase[0].minor.yy454 = 0
        Dim pExpr As SqliteExpr Ptr = sqlite3ParserExprIsNull(pParse, opcode, pLeft)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_NOT_NULL
        If rhsCount <> 3 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        pBase[0].minor.yy454 = 0
        Dim pExpr As SqliteExpr Ptr = _
            sqlite3ParserExprIsNull(pParse, TK_NOTNULL, pLeft)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_IS, YYRULE_EXPR_IS_NOT, _
         YYRULE_EXPR_IS_NOT_DISTINCT, YYRULE_EXPR_IS_DISTINCT
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - (rhsCount - 1)
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim pRight As SqliteExpr Ptr = _
            CPtr(SqliteExpr Ptr, pBase[rhsCount - 1].minor.yy454)
        pBase[0].minor.yy454 = 0
        pBase[rhsCount - 1].minor.yy454 = 0
        Dim opcode As SQLITE_C_INT = TK_IS
        If ruleNumber = YYRULE_EXPR_IS_NOT OrElse _
           ruleNumber = YYRULE_EXPR_IS_DISTINCT Then opcode = TK_ISNOT
        Dim pExpr As SqliteExpr Ptr = _
            sqlite3ParserExprIs(pParse, opcode, pLeft, pRight)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_EXPR_OR, YYRULE_EXPR_RELATIONAL, YYRULE_EXPR_EQUALITY, _
         YYRULE_EXPR_BITWISE, YYRULE_EXPR_ADDITIVE, YYRULE_EXPR_MULTIPLICATIVE, _
         YYRULE_EXPR_CONCAT
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 2
        Dim pLeft As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim pRight As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        pBase[0].minor.yy454 = 0
        pBase[2].minor.yy454 = 0
        Dim pExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, pBase[1].major, pLeft, pRight)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_BETWEEN_OP
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 0

    Case YYRULE_NOT_BETWEEN_OP
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy144 = 1

    Case YYRULE_EXPR_BETWEEN
        If rhsCount <> 5 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim pBase As sqlite3ParserStackEntry Ptr = pTop - 4
        Dim pValue As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[0].minor.yy454)
        Dim invertResult As SQLITE_C_INT = pBase[1].minor.yy144
        Dim pLowerExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[2].minor.yy454)
        Dim pUpperExpr As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pBase[4].minor.yy454)
        pBase[0].minor.yy454 = 0
        pBase[2].minor.yy454 = 0
        pBase[4].minor.yy454 = 0

        Dim pBounds As SqliteExprList Ptr = _
            sqlite3ExprListAppend(pParse, 0, pLowerExpr)
        If pBounds = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprDelete(pParse->db, pUpperExpr)
            sqlite3ExprDelete(pParse->db, pValue)
            sqlite3ExprListDelete(pParse->db, pBounds)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pBounds = sqlite3ExprListAppend(pParse, pBounds, pUpperExpr)
        If pBounds = 0 OrElse pParse->db->mallocFailed <> 0 Then
            sqlite3ExprDelete(pParse->db, pValue)
            sqlite3ExprListDelete(pParse->db, pBounds)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If

        Dim pBetween As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, TK_BETWEEN, pValue, 0)
        If pBetween = 0 Then
            sqlite3ExprListDelete(pParse->db, pBounds)
            Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pBetween->x.pList = pBounds
        sqlite3ExprSetHeightAndFlags(pParse, pBetween)
        If pParse->db->mallocFailed <> 0 OrElse pParse->nErr <> 0 Then
            sqlite3ExprDelete(pParse->db, pBetween)
            Dim rc As SQLITE_C_INT = IIf( _
                pParse->db->mallocFailed <> 0, SQLITE_NOMEM, SQLITE_ERROR)
            Return sqlite3ParserActionError(pParse, rc)
        End If
        If invertResult <> 0 Then
            pBetween = sqlite3PExpr(pParse, TK_NOT, pBetween, 0)
            If pBetween = 0 Then _
                Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        End If
        pResult->yy454 = pBetween

    Case YYRULE_EXPR_NOT, YYRULE_EXPR_BITNOT, YYRULE_EXPR_UNARY_SIGN
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        Dim unaryOpcode As SQLITE_C_INT
        Select Case ruleNumber
        Case YYRULE_EXPR_NOT
            unaryOpcode = TK_NOT
        Case YYRULE_EXPR_BITNOT
            unaryOpcode = TK_BITNOT
        Case YYRULE_EXPR_UNARY_SIGN
            If pTop[-1].major = TK_PLUS Then
                unaryOpcode = TK_UPLUS
            ElseIf pTop[-1].major = TK_MINUS Then
                unaryOpcode = TK_UMINUS
            Else
                Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
            End If
        End Select
        Dim pOperand As SqliteExpr Ptr = CPtr(SqliteExpr Ptr, pTop->minor.yy454)
        pTop->minor.yy454 = 0
        Dim pExpr As SqliteExpr Ptr = sqlite3PExpr( _
            pParse, unaryOpcode, pOperand, 0)
        If pExpr = 0 Then Return sqlite3ParserActionError(pParse, SQLITE_NOMEM)
        pResult->yy454 = pExpr

    Case YYRULE_SCLP_SELCOLLIST_COMMA
        If rhsCount <> 2 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult->yy14 = pTop[-1].minor.yy14

    Case YYRULE_SELECTNOWITH_ONESELECT, YYRULE_AS_ID_STRING, _
         YYRULE_EXPR_TERM, YYRULE_EXPRLIST_NEXPRLIST
        If rhsCount <> 1 Then Return sqlite3ParserActionError(pParse, SQLITE_CORRUPT)
        pResult[0] = pTop->minor

    Case Else
        If ruleNumber >= YYNRULE_WITH_ACTION Then
            ' Lemon's default action copies the first RHS value. The first
            ' symbol is below the stack top for multi-symbol productions.
            If rhsCount > 0 Then pResult[0] = pTop[1 - rhsCount].minor
            Return SQLITE_OK
        End If
        Return sqlite3ParserActionError(pParse, SQLITE_ERROR)
    End Select

    Return SQLITE_OK
End Function

/' end of sqlite3_parser_semantics.bas '/
