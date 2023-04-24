# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary", "platform_test")

go_library(
    name = "cgo_lib",
    srcs = ["cgo.go"],
    cgo = True,
    importpath = "github.com/uber/hermetic_cc_toolchain/test/cgo",
    visibility = ["//visibility:private"],
)

go_test(
    name = "cgo_test",
    srcs = ["cgo_test.go"],
    embed = [":cgo_lib"],
)

go_binary(
    name = "cgo",
    embed = [":cgo_lib"],
    gc_linkopts = select({
        "@platforms//os:macos": [
            "-w",  # https://github.com/ziglang/zig/issues/15439
            "-buildmode=pie",  # https://github.com/ziglang/zig/issues/15438
        ],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
)

[
    platform_binary(
        name = "cgo_{}".format(name),
        src = "cgo",
        platform = platform,
    )
    for name, platform in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl"),
        ("linux_amd64_gnu.2.19", "//libc_aware/platform:linux_amd64_gnu.2.19"),
        ("linux_arm64_musl", "//libc_aware/platform:linux_arm64_musl"),
        ("linux_arm64_gnu.2.28", "//libc_aware/platform:linux_arm64_gnu.2.28"),
        ("darwin_amd64", "//platform:darwin_amd64"),
    ]
]

[
    platform_test(
        name = "cgo_test_{}".format(name),
        src = "cgo_test",
        platform = platform,
    )
    for name, platform, is_arm64 in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl", False),
        ("linux_amd64_gnu.2.19", "//libc_aware/platform:linux_amd64_gnu.2.19", False),
    ]
]
