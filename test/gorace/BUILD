# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("@rules_go//go:def.bzl", "go_binary", "go_library", "go_test")

go_library(
    name = "gorace_lib",
    srcs = ["main.go"],
    # keep
    cgo = True,
    importpath = "github.com/uber/hermetic_cc_toolchain/test/gorace",
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
    race = "on",
)
