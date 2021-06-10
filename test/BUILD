load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")

go_library(
    name = "go_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "gognu",
    embed = [":go_lib"],
    visibility = ["//visibility:public"],
)

go_binary(
    name = "gomusl",
    embed = [":go_lib"],
    static = "on",
    target_compatible_with = select({
        "@platforms//os:linux": ["@zig_sdk//:libc_musl"],
        "//conditions:default": [],
    }),
    visibility = ["//visibility:public"],
)
