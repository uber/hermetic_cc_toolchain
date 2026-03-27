// Copyright 2025 Uber Technologies, Inc.
// Licensed under the MIT License

// Minimal shared library used to verify that the zig cc toolchain embeds a
// SONAME (DT_SONAME) in shared libraries it produces. Without the soname
// feature in zig_cc_toolchain.bzl, the DT_SONAME entry is absent and
// binaries that link against this library record the full build-time path in
// DT_NEEDED, causing runtime loading failures.

int add(int a, int b) {
    return a + b;
}
