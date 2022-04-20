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
        name = "go_{}".format(name),
        src = "go",
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
        name = "go_test_{}".format(name),
        src = "go_test",
        platform = platform,
    )
    for name, platform in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl"),
        ("linux_amd64_gnu.2.19", "//libc_aware/platform:linux_amd64_gnu.2.19"),
        ("linux_arm64_musl", "//libc_aware/platform:linux_arm64_musl"),
        ("linux_arm64_gnu.2.28", "//libc_aware/platform:linux_arm64_gnu.2.28"),
    ]
]
