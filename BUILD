# Copyright 2023 Uber Technologies, Inc.
# Licensed under the Apache License, Version 2.0

load("@bazel_gazelle//:def.bzl", "gazelle")

# gazelle:map_kind go_binary go_binary //rules:rules_go.bzl

# gazelle:build_file_name BUILD
# gazelle:prefix github.com/uber/bazel-zig-cc
# gazelle:exclude tools.go
# gazelle:exclude tools/releaser/zopfli.go

gazelle(name = "gazelle")

gazelle(
    name = "gazelle-update-repos",
    args = [
        "-from_file=go.mod",
        "-to_macro=repositories.bzl%go_repositories",
        "-prune",
    ],
    command = "update-repos",
)
