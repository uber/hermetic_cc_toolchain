# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library", "go_test")
load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")

go_library(
    name = "plugin_lib",
    srcs = ["plugin.go"],
    importpath = "github.com/uber/hermetic_cc_toolchain/test/plugin",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "plugin.so",
    embed = [":plugin_lib"],
    linkmode = "plugin",
    visibility = ["//visibility:private"],
)

# gazelle:exclude plugin_test.go
[
    (
        platform_binary(
            name = "plugin_{}.so".format(name),
            src = ":plugin.so",
            platform = platform,
            visibility = ["//visibility:private"],
        ),
        go_test(
            name = "plugin_{}_test".format(name),
            srcs = ["plugin_test.go"],
            data = [":plugin_{}.so".format(name)],
            env = {
                "PLUGIN_BINARY": "$(rlocationpath :plugin_{}.so)".format(name),
                "PLUGIN_ELF_MACH": elf_mach,
            },
            deps = ["@io_bazel_rules_go//go/runfiles:go_default_library"],
        ),
    )
    for (name, platform, elf_mach) in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl", "x86_64"),
        ("linux_amd64", "//libc_aware/platform:linux_amd64_gnu.2.28", "x86_64"),
        ("linux_arm64", "//libc_aware/platform:linux_arm64_gnu.2.28", "aarch64"),
    ]
]

test_suite(
    name = "plugin_test",
    tests = [
        ":plugin_{}_test".format(name)
        for name in (
            "linux_amd64_musl",
            "linux_amd64",
            "linux_arm64",
        )
    ],
)
