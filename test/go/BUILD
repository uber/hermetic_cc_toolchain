load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")
load("//rules:rules_go.bzl", "go_binary")
load("@bazel-zig-cc//rules:platform.bzl", "platform_binary", "platform_test")

go_library(
    name = "go_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "git.sr.ht/~motiejus/bazel-zig-cc/test/go",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "go",
    embed = [":go_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "go_test",
    srcs = ["hello_test.go"],
    embed = [":go_lib"],
)

[
    platform_binary(
        name = "go_{}".format(toolchain),
        src = "go",
        extra_toolchains = ["//toolchain:{}".format(toolchain)],
        platform = "//platform:{}".format(platform),
    )
    for platform, toolchain in [
        ("linux_amd64", "linux_amd64_musl"),
        ("linux_amd64", "linux_amd64_gnu.2.19"),
        ("linux_arm64", "linux_arm64_musl"),
        ("linux_arm64", "linux_arm64_gnu.2.28"),
        ("darwin_amd64", "darwin_amd64"),
    ]
]

[
    platform_test(
        name = "go_test_{}".format(toolchain),
        src = "go_test",
        extra_toolchains = ["//toolchain:{}".format(toolchain)],
        platform = "//platform:{}".format(platform),
    )
    for platform, toolchain in [
        ("linux_amd64", "linux_amd64_musl"),
        ("linux_amd64", "linux_amd64_gnu.2.19"),
        ("linux_arm64", "linux_arm64_musl"),
        ("linux_arm64", "linux_arm64_gnu.2.28"),
    ]
]
