load("@bazel_gazelle//:def.bzl", "gazelle")

gazelle(
    name = "gazelle",
    visibility = ["//visibility:public"],
)

gazelle(
    name = "gazelle-update-repos",
    args = [
        "-from_file=go.mod",
        "-to_macro=repositories.bzl%go_repositories",
        "-prune",
    ],
    command = "update-repos",
    visibility = ["//visibility:public"],
)
