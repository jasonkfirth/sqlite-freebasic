# Build the FreeBASIC converter for SQLite's generated C headers.

FBC ?= fbc
TARGET ?= build/sqlite_codegen

.PHONY: all clean

all: $(TARGET)

$(TARGET): sqlite_codegen.bas
	mkdir -p $(dir $@)
	$(FBC) -w all -x $@ $<

clean:
	rm -rf build

# end of fb_tools/sqlite_codegen/Makefile
