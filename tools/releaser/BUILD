# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

load("//rules:rules_go.bzl", "go_binary")
load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "releaser_lib",
    srcs = ["main.go"],
    importpath = "github.com/uber/hermetic_cc_toolchain/tools/releaser",
    visibility = ["//visibility:private"],
)

go_binary(
    name = "releaser",
    embed = [":releaser_lib"],
    visibility = ["//visibility:public"],
)

go_test(
    name = "releaser_test",
    srcs = ["main_test.go"],
    embed = [":releaser_lib"],
)
