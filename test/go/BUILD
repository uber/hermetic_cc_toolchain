load("@io_bazel_rules_go//go:def.bzl", "go_binary", "go_library")

# go build -ldflags "-linkmode external -extldflags -static" hello.go
go_library(
    name = "go_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test/go",
    visibility = ["//visibility:private"],
    target_compatible_with = select({
        "@platforms//os:linux": ["@com_github_ziglang_zig//:musl"],
        "//conditions:default": [],
    }),
)

go_binary(
    name = "go",
    embed = [":go_lib"],
    visibility = ["//visibility:public"],
    static = "on",
)
