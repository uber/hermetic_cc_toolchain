# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@bazel-zig-cc//toolchain/libc:defs.bzl", "declare_libcs")

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
