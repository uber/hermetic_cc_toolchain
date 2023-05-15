workspace(name = "hermetic_cc_toolchain")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

RULESGO_VERSION = "v0.39.1"

http_archive(
    name = "io_bazel_rules_go",
    sha256 = "6dc2da7ab4cf5d7bfc7c949776b1b7c733f05e56edc4bcd9022bb249d2e2a996",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/rules_go/releases/download/{0}/rules_go-{0}.zip".format(RULESGO_VERSION),
        "https://github.com/bazelbuild/rules_go/releases/download/{0}/rules_go-{0}.zip".format(RULESGO_VERSION),
    ],
)

PROTOBUF_VERSION = "23.0"

http_archive(
    name = "com_google_protobuf",
    sha256 = "b29fc5fc13926f347b7a8b676ae1e63f7ccdb92c2fc8ca326bc3a883dcc168ac",
    strip_prefix = "protobuf-{}".format(PROTOBUF_VERSION),
    urls = [
        "https://github.com/protocolbuffers/protobuf/releases/download/v{0}/protobuf-{0}.tar.gz".format(PROTOBUF_VERSION),
    ],
)

load("@com_google_protobuf//:protobuf_deps.bzl", "protobuf_deps")

protobuf_deps()

GAZELLE_VERSION = "v0.30.0"

http_archive(
    name = "bazel_gazelle",
    sha256 = "727f3e4edd96ea20c29e8c2ca9e8d2af724d8c7778e7923a854b2c80952bc405",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-gazelle/releases/download/{0}/bazel-gazelle-{0}.tar.gz".format(GAZELLE_VERSION),
        "https://github.com/bazelbuild/bazel-gazelle/releases/download/{0}/bazel-gazelle-{0}.tar.gz".format(GAZELLE_VERSION),
    ],
)

load("@io_bazel_rules_go//go:deps.bzl", "go_download_sdk", "go_register_toolchains", "go_rules_dependencies")
load("@bazel_gazelle//:deps.bzl", "gazelle_dependencies")

go_rules_dependencies()

# use latest stable.
go_download_sdk(
    name = "go_sdk",
    version = "1.20.4",
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
