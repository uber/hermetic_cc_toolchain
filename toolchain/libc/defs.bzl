# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "LIBCS")

def declare_libcs():
    for libc in LIBCS:
        native.constraint_value(
            name = libc,
            constraint_setting = "variant",
        )
