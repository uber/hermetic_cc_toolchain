// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

// This file tests that problematic functions (glibc-hacks) work.
// Also see https://github.com/ziglang/zig/issues/9485

#define _FILE_OFFSET_BITS 64
#include <unistd.h>
#include <fcntl.h>
#include <resolv.h>
#include <stdio.h>

int main() {
    printf("Your lucky numbers are %p and %p\n", fcntl, res_search);
    return 0;
}
