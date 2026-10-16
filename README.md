# SQLite FreeBASIC port

This repository contains the FreeBASIC SQLite engine in `fb_src/` and the
supporting generated-table utility in `fb_tools/sqlite_codegen/`. The port is
released to the public domain; see [LICENSE.md](LICENSE.md). Detailed porting
notes and current status are in [fb_src/README.md](fb_src/README.md).

## Build

Install FreeBASIC and GNU Make, then run:

```sh
make -C fb_src
```

This builds the checked-in FreeBASIC units and generated includes. Build
products go under `fb_src/build/`.

Some regeneration and reconciliation targets in `fb_src/Makefile` also use an
adjacent SQLite source checkout (`../src/` and `../tool/`). Targets that invoke
the C2FB converter require that tool separately. C2FB is not included here
because its own project declares GPL-3.0-or-later; the engine port and the
supporting code included in this repository remain public domain.
