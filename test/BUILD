load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "hello_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test",
    visibility = ["//visibility:private"],
    deps = [
        "@com_github_datadog_zstd//:go_default_library",
        "@com_github_mattn_go_sqlite3//:go_default_library",
    ],
)

go_binary(
    name = "hello",
    embed = [":hello_lib"],
    gc_linkopts = select({
        "@platforms//os:macos": [
            "-s",
            "-w",
            "-buildmode=pie",
        ],
        "//conditions:default": [],
    }),
    static = "on",
    visibility = ["//visibility:public"],
)
