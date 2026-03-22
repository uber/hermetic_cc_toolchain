// Copyright 2025 Uber Technologies, Inc.
// Licensed under the MIT License

// Tests that Zig correctly handles the "-l :filename.so" linking syntax,
// where the library name is separated from -l by a space.
//
// In Zig 0.14.0, the linker reported:
//   ld.lld: error: unable to find library -l:mylib.so
// when invoked with "-l" and ":mylib.so" as separate arguments.
//
// See https://github.com/ziglang/zig/issues/23287

#include <stdio.h>

// Forward declaration to avoid needing a header file.
extern int greet(void);

int main(void) {
    printf("%d\n", greet());
    return 0;
}
