load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")
load("//rules:rules_go.bzl", "go_binary")

go_library(
    name = "gorace_lib",
    srcs = ["main.go"],
    # keep
    cgo = True,
    importpath = "git.sr.ht/~motiejus/bazel-zig-cc/test/gorace",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "gorace",
    embed = [":gorace_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "gorace_test",
    srcs = ["main_test.go"],
    embed = [":gorace_lib"],
    gc_linkopts = ["-linkmode=external"],
    race = "on",
)
