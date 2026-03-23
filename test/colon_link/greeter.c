// Copyright 2025 Uber Technologies, Inc.
// Licensed under the MIT License

// Shared library used for testing the "-l :filename.so" linking syntax.
// See https://github.com/ziglang/zig/issues/23287

int greet(void) {
    return 42;
}
