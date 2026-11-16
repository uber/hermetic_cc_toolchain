# Copyright 2023 Uber Technologies, Inc.
# Copyright 2026 toolchains_zig_cc contributors
# Licensed under the MIT License

load("@toolchains_zig_cc//toolchain/libc:defs.bzl", "declare_libcs")

package(
    default_visibility = ["//visibility:public"],
)

constraint_setting(
    name = "variant",
    default_constraint_value = "unconstrained",
)

constraint_value(
    name = "unconstrained",
    constraint_setting = "variant",
)

declare_libcs()
