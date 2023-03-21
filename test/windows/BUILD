# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary", "platform_test")

cc_binary(
    name = "winver",
    srcs = ["main.c"],
    tags = ["manual"],
)

platform_binary(
    name = "winver_windows_amd64",
    src = "winver",
    platform = "//platform:windows_amd64",
)

platform_binary(
    name = "winver_windows_arm64",
    src = "winver",
    platform = "//platform:windows_arm64",
)
