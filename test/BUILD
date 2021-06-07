load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")

cc_binary(
    name = "hello",
    srcs = ["hello.cpp"],
    target_compatible_with = select({
        "@platforms//os:linux": ["@com_github_ziglang_zig//:musl"],
        "//conditions:default": [],
    }),
)

cc_binary(
    name = "exception",
    srcs = ["exception.cpp"],
)

# go build -ldflags "-linkmode external -extldflags -static" hello.go

go_library(
    name = "test_lib",
    srcs = [
        "exception.cpp",
        "hello.cpp",
        "hello.go",
    ],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "test",
    embed = [":test_lib"],
    visibility = ["//visibility:public"],
)
