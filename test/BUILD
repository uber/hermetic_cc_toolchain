load("//rules:go_binary_override.bzl", "go_binary")
load("@io_bazel_rules_go//go:def.bzl", "go_library")

go_library(
    name = "hello_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test",
    visibility = ["//visibility:private"],
    deps = [
        "@com_github_datadog_zstd//:zstd",
        "@com_github_mattn_go_sqlite3//:go-sqlite3",
    ],
)

go_binary(
    name = "hello",
    embed = [":hello_lib"],
    static = "on",
    visibility = ["//visibility:public"],
)
