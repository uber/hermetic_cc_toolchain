load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")
load("//rules:rules_go.bzl", "go_binary")

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
    static = "on",
    visibility = ["//visibility:public"],
)

go_test(
    name = "go_test",
    srcs = ["hello_test.go"],
    embed = [":go_lib"],
)
