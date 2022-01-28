load("//rules:rules_go.bzl", "go_binary")
load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "hello_lib",
    srcs = ["hello.go"],
    cgo = True,
    importpath = "github.com/motiejus/bazel-zig-cc/test",
    visibility = ["//visibility:private"],
    deps = ["@com_github_mattn_go_sqlite3//:go-sqlite3"],
)

go_binary(
    name = "hello",
    embed = [":hello_lib"],
    static = "on",
    visibility = ["//visibility:public"],
)

go_test(
    name = "test_test",
    srcs = ["hello_test.go"],
    embed = [":test_lib"],
)
