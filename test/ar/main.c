// Copyright 2026 Uber Technologies, Inc.
// Licensed under the MIT License

// Links against an archive containing member.c.
// See https://github.com/ziglang/zig/issues/25694

extern int add(int a, int b);

int main(void) {
    return add(1, 2) - 3;
}
