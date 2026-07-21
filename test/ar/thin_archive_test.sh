#!/usr/bin/env bash

# Copyright 2026 Uber Technologies, Inc.
# Licensed under the MIT License

# Exercises archive creation and consumption around thin archives
# (https://github.com/ziglang/zig/issues/25694). Two modes:
#
#   wrapper: the toolchain's `ar` wrapper is asked for a thin archive
#            (`rcsT`). The wrapper strips the thin-archive request, so the
#            result must be a regular archive that links fine.
#
#   raw:     `zig ar` is invoked directly (bypassing the wrapper) to create a
#            genuinely thin archive, and linking against it must SUCCEED:
#            ziglang/zig#25694 is fixed in Zig 0.16. This is the inverse of
#            the 0.15 canary — if a future Zig regresses thin-archive
#            reading, this test fails. The wrapper still strips thin-archive
#            requests for consistency with the 0.15 line; delete
#            stripThinArchiveFlags once 0.15 support is dropped.

set -euo pipefail

mode=$1

zig="$TEST_SRCDIR/$ZIG"
sdk=$(dirname "$zig")
cxx="$sdk/tools/x86_64-linux-musl/c++"
ar_wrapper="$sdk/tools/ar"
work="$TEST_TMPDIR"

# The c++ wrapper derives its zig cache location from HOME.
export HOME="$work"

"$cxx" -c test/ar/member.c -o "$work/member.o"

case "$mode" in
wrapper)
    "$ar_wrapper" rcsT "$work/libmember.a" "$work/member.o"

    magic=$(head -c 7 "$work/libmember.a")
    if [[ "$magic" != '!<arch>' ]]; then
        echo "FAIL: wrapper ar produced '$magic', want a regular '!<arch>' archive" >&2
        exit 1
    fi

    "$cxx" test/ar/main.c "$work/libmember.a" -o "$work/main"
    ;;
raw)
    ZIG_LIB_DIR="$sdk/lib" "$zig" ar rcsT "$work/libmember.a" "$work/member.o"

    magic=$(head -c 7 "$work/libmember.a")
    if [[ "$magic" != '!<thin>' ]]; then
        echo "FAIL: zig ar rcsT produced '$magic', want a thin '!<thin>' archive" >&2
        exit 1
    fi

    if ! "$cxx" test/ar/main.c "$work/libmember.a" -o "$work/main" 2>"$work/link.err"; then
        echo "FAIL: linking a thin archive failed; ziglang/zig#25694 has" >&2
        echo "regressed (it is fixed in Zig 0.16):" >&2
        cat "$work/link.err" >&2
        exit 1
    fi
    ;;
*)
    echo "usage: $0 wrapper|raw" >&2
    exit 1
    ;;
esac
