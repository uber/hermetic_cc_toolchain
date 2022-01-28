load("@bazel_gazelle//:def.bzl", "gazelle")
load("@com_github_bazelbuild_buildtools//buildifier:def.bzl", "buildifier")

# gazelle:map_kind go_binary go_binary //rules:rules_go.bzl

# gazelle:build_file_name BUILD
# gazelle:prefix git.sr.ht/~motiejus/bazel-zig-cc
gazelle(name = "gazelle")

buildifier(name = "buildifier")
