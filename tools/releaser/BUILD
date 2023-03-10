# Copyright 2023 Uber Technologies, Inc.
# Licensed under the Apache License, Version 2.0

load("//rules:rules_go.bzl", "go_binary")
load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "releaser_lib",
    srcs = [
        "main.go",
        "zopfli.go",  # keep
    ],
    importpath = "github.com/uber/bazel-zig-cc/tools/releaser",
    visibility = ["//visibility:private"],
    deps = ["@zopfli//:go_zopfli"],  # keep
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
