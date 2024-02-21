# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")

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
    visibility = ["//visibility:public"],
)

[
    (
        platform_binary(
            name = "cgo_{}".format(name),
            src = "cgo",
            platform = platform,
        ),
    )
    for name, platform in [
        (
            "linux_amd64_musl",
            "//libc_aware/platform:linux_amd64_musl",
        ),
        (
            "linux_amd64_gnu.2.28",
            "//libc_aware/platform:linux_amd64_gnu.2.28",
        ),
        (
            "windows_amd64",
            "//platform:windows_amd64",
        ),
        (
            "windows_arm64",
            "//platform:windows_arm64",
        ),
    ]
]
