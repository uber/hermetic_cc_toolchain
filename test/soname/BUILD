# Copyright 2025 Uber Technologies, Inc.
# Licensed under the MIT License

# Tests that the zig cc toolchain embeds a SONAME (DT_SONAME) in shared
# libraries. Without the soname feature in zig_cc_toolchain.bzl, DT_SONAME
# is absent: the linker records the full build-time path in DT_NEEDED of
# any binary that links against the library, breaking runtime loading.

load("@rules_go//go:def.bzl", "go_test")

cc_binary(
    name = "libadd.so",
    srcs = ["lib.c"],
    linkshared = True,
)

go_test(
    name = "soname_test",
    srcs = ["soname_test.go"],
    data = [":libadd.so"],
    env = {
        "LIB": "$(rlocationpath :libadd.so)",
    },
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    deps = ["@rules_go//go/runfiles"],
)
