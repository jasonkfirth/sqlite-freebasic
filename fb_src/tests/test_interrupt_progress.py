#!/usr/bin/env python3
"""
Project: SQLite FreeBASIC port
File: test_interrupt_progress.py
Purpose: Verify interrupts stop a running SQL preparation.
Responsibilities: Build the FreeBASIC library and run a progress-callback
  regression entirely inside a temporary directory.
This file intentionally does NOT contain: SQLite engine or mutex code.
"""

import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile


def run(command, environment=None):
    result = subprocess.run(
        command, text=True, capture_output=True, env=environment)
    if result.returncode != 0:
        details = (result.stdout + result.stderr).strip()
        raise RuntimeError(
            f"Command failed (exit {result.returncode}): "
            f"{shlex.join(command)}\n{details}")
    return result.stdout


def write_interrupt_client(path):
    path.write_text(
        '#include once "sqlite3_api_constants.bi"\n'
        '#include once "sqlite3_api_declarations.bi"\n'
        'Dim Shared progressCallCount As Long\n'
        'Dim Shared interruptWasVisible As Long\n'
        'Function interruptFromProgress CDecl(ByVal context As Any Ptr) As SQLITE_C_INT\n'
        '    progressCallCount += 1\n'
        '    sqlite3_interrupt(context)\n'
        '    If sqlite3_is_interrupted(context) <> 0 Then interruptWasVisible = 1\n'
        '    Return 0\n'
        'End Function\n'
        'Dim initializeCode As SQLITE_C_INT = sqlite3_initialize()\n'
        'If initializeCode <> SQLITE_OK Then\n'
        '    Print "initialize result "; initializeCode\n'
        '    Sleep 1\n'
        '    End 5\n'
        'End If\n'
        'Dim mutexProbe As Any Ptr = sqlite3_mutex_alloc(0)\n'
        'If mutexProbe = 0 Then\n'
        '    Print "mutex allocation returned zero"\n'
        '    Sleep 1\n'
        '    End 6\n'
        'End If\n'
        'sqlite3_mutex_free(mutexProbe)\n'
        'Dim database As Any Ptr\n'
        'Dim openCode As SQLITE_C_INT = sqlite3_open(StrPtr(":memory:"), @database)\n'
        'If openCode <> SQLITE_OK Then\n'
        '    Print "open result "; openCode\n'
        '    Sleep 1\n'
        '    End 1\n'
        'End If\n'
        'sqlite3_progress_handler(database, 1, ProcPtr(interruptFromProgress), database)\n'
        'Dim query As String = "SELECT 1"\n'
        'For index As Long = 2 To 400\n'
        '    query &= " UNION ALL SELECT " & Trim(Str(index))\n'
        'Next\n'
        'Dim statement As Any Ptr\n'
        'Dim tail As Const ZString Ptr\n'
        'Dim resultCode As SQLITE_C_INT = sqlite3_prepare_v2( _\n'
        '    database, StrPtr(query), -1, @statement, @tail)\n'
        'If progressCallCount = 0 Then End 2\n'
        'If interruptWasVisible = 0 Then End 4\n'
        'If resultCode <> SQLITE_INTERRUPT Then End 3\n'
        'If statement <> 0 Then sqlite3_finalize(statement)\n'
        'sqlite3_progress_handler(database, 0, 0, 0)\n'
        'sqlite3_close(database)\n',
        encoding="utf-8",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fbc", default="fbc")
    parser.add_argument("--make", default="make")
    parser.add_argument("--threadsafe", choices=("0", "1"), default="1")
    arguments = parser.parse_args()
    source_root = Path(__file__).resolve().parents[1]
    fbc_command = shlex.split(arguments.fbc)
    make_command = shlex.split(arguments.make)
    if not fbc_command or not make_command:
        parser.error("compiler and make commands must not be empty")

    with tempfile.TemporaryDirectory(prefix="sqlite-interrupt-progress-") as directory:
        work = Path(directory)
        library = work / "libsqlite3-fb.so"
        client_source = work / "interrupt_progress.bas"
        client_executable = work / "interrupt_progress"
        write_interrupt_client(client_source)

        run(make_command + [
            "-C", str(source_root), "all",
            "THREADSAFE=" + arguments.threadsafe,
            "TARGET=" + str(library), "FBC=" + shlex.join(fbc_command),
        ])
        thread_flags = ["-mt"] if arguments.threadsafe == "1" else []
        run(fbc_command + [
            *thread_flags, "-w", "all", "-i", str(source_root),
            "-p", str(work), "-l", "sqlite3-fb",
            str(client_source), "-x", str(client_executable),
        ])

        environment = os.environ.copy()
        current_library_path = environment.get("LD_LIBRARY_PATH", "")
        environment["LD_LIBRARY_PATH"] = str(work)
        if current_library_path:
            environment["LD_LIBRARY_PATH"] += os.pathsep + current_library_path
        run([str(client_executable)], environment)
    print("Interrupt raised by the progress callback stopped SQL preparation.")


if __name__ == "__main__":
    main()

# end of test_interrupt_progress.py
