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
#            genuinely thin archive, and linking against it must FAIL with
#            the ziglang/zig#25694 error. This is a canary: when a Zig
#            upgrade makes this test fail, upstream has fixed #25694 —
#            flip this mode's expectation and delete stripThinArchiveFlags
#            from toolchain/zig-wrapper.zig.

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

    if "$cxx" test/ar/main.c "$work/libmember.a" -o "$work/main" 2>"$work/link.err"; then
        echo "FAIL: linking a thin archive succeeded: ziglang/zig#25694 appears" >&2
        echo "to be fixed upstream. Flip this test's expectation and delete" >&2
        echo "stripThinArchiveFlags from toolchain/zig-wrapper.zig." >&2
        exit 1
    fi
    if ! grep -q 'unexpected token in LD script' "$work/link.err"; then
        echo "FAIL: link failed, but not with the ziglang/zig#25694 error:" >&2
        cat "$work/link.err" >&2
        exit 1
    fi
    ;;
*)
    echo "usage: $0 wrapper|raw" >&2
    exit 1
    ;;
esac
