# Copyright 2023 Uber Technologies, Inc.
# Copyright 2026 toolchains_zig_cc contributors
# Licensed under the MIT License

load("@toolchains_zig_cc//toolchain/private:defs.bzl", "LIBCS")

def declare_libcs():
    for libc in LIBCS:
        native.constraint_value(
            name = libc,
            constraint_setting = "variant",
        )
