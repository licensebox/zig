#!/usr/bin/env bash
set -euo pipefail
mkdir -p build
zig fmt --check build.zig src tests examples
zig build test -Dnative-lib-dir="$LICENSEBOX_LIB_DIR"
zig build -Doptimize=ReleaseSafe -Dnative-lib-dir="$LICENSEBOX_LIB_DIR" --prefix "$PWD/build/install"
# Compile a separate consumer from the installed module source.
zig build-exe -lc -L"$LICENSEBOX_LIB_DIR" -llicensebox --dep licensebox -Mroot=examples/status.zig -Mlicensebox=build/install/share/licensebox/licensebox.zig -femit-bin=build/consumer
