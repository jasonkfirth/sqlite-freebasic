# FreeBASIC implementation

This directory contains the SQLite engine port, generated parser and opcode
tables, build rules, and porting inventories. It builds the checked-in
FreeBASIC units with:

```sh
make -C fb_src
```

For current compiler and test qualification, see the repository's
[QUALIFICATION.md](../QUALIFICATION.md). The archived chronological log is
[docs/DEVELOPMENT_HISTORY.md](../docs/DEVELOPMENT_HISTORY.md).

Regeneration targets that read SQLite's C source tree or invoke C2FB are
optional and require those tools separately. The default library build uses
the checked-in FreeBASIC sources and tables.
