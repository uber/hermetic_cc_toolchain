workspace(
    name = "bazel-zig-cc",
)

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "io_bazel_rules_go",
    sha256 = "16e9fca53ed6bd4ff4ad76facc9b7b651a89db1689a2877d6fd7b82aa824e366",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/rules_go/releases/download/v0.34.0/rules_go-v0.34.0.zip",
        "https://github.com/bazelbuild/rules_go/releases/download/v0.34.0/rules_go-v0.34.0.zip",
    ],
)

http_archive(
    name = "bazel_gazelle",
    sha256 = "5982e5463f171da99e3bdaeff8c0f48283a7a5f396ec5282910b9e8a49c0dd7e",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-gazelle/releases/download/v0.25.0/bazel-gazelle-v0.25.0.tar.gz",
        "https://github.com/bazelbuild/bazel-gazelle/releases/download/v0.25.0/bazel-gazelle-v0.25.0.tar.gz",
    ],
)

load("@io_bazel_rules_go//go:deps.bzl", "go_download_sdk", "go_register_toolchains", "go_rules_dependencies")
load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")

go_rules_dependencies()

# use latest stable.
go_download_sdk(
    name = "go_sdk",
    version = "1.18.3",
)

go_register_toolchains()

load("//:repositories.bzl", "go_repositories")

# gazelle:repository_macro repositories.bzl%go_repositories
go_repositories()

gazelle_dependencies(go_repository_default_config = "@//:WORKSPACE")

load(
    "//toolchain:defs.bzl",
    zig_toolchains = "toolchains",
)

zig_toolchains()

register_toolchains(
    # if no `--platform` is specified, these toolchains will be used for
    # (linux,darwin,windows)x(amd64,arm64)
    "@zig_sdk//toolchain:linux_amd64_gnu.2.19",
    "@zig_sdk//toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//toolchain:darwin_amd64",
    "@zig_sdk//toolchain:darwin_arm64",
    "@zig_sdk//toolchain:windows_amd64",
    "@zig_sdk//toolchain:windows_arm64",

    # amd64 toolchains for libc-aware platforms:
    "@zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.19",
    "@zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.28",
    "@zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.31",
    "@zig_sdk//libc_aware/toolchain:linux_amd64_musl",
    # arm64 toolchains for libc-aware platforms:
    "@zig_sdk//libc_aware/toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//libc_aware/toolchain:linux_arm64_musl",
)
