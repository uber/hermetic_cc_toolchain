load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")
load("@rules_go//go:def.bzl", "go_library", "go_test")

cc_binary(
    name = "which_libc",
    srcs = ["main.c"],
)

_LINUX_AMD64 = [
    "@platforms//os:linux",
    "@platforms//cpu:x86_64",
]

_DARWIN_AMD64 = [
    "@platforms//os:macos",
    "@platforms//cpu:x86_64",
]

_DARWIN_ARM64 = [
    "@platforms//os:macos",
    "@platforms//cpu:aarch64",
]

_WINDOWS_AMD64 = [
    "@platforms//os:windows",
    "@platforms//cpu:x86_64",
]

[
    (
        platform_binary(
            name = "which_libc_{}".format(name),
            src = "which_libc",
            platform = platform,
            tags = tags,
        ),
        go_test(
            name = "test_libc_{}".format(name),
            data = [":which_libc_{}".format(name)],
            embed = [":c_test"],
            env = {
                "WANT": want,
                "BINARY": "$(rlocationpath which_libc_{})".format(name),
            },
            target_compatible_with = compatible_with,
        ),
    )
    for name, platform, compatible_with, want, tags in [
        (
            "linux_amd64_musl",
            "//libc_aware/platform:linux_amd64_musl",
            _LINUX_AMD64,
            "^linux non-glibc",
            [],
        ),
        (
            "linux_amd64_gnu.2.28",
            "//libc_aware/platform:linux_amd64_gnu.2.28",
            _LINUX_AMD64,
            "^linux glibc_2.28",
            [],
        ),
        (
            "linux_amd64",
            "//platform:linux_amd64",
            _LINUX_AMD64,
            "^linux glibc_2.28",
            [],
        ),
        (
            "windows_amd64",
            "//platform:windows_amd64",
            _WINDOWS_AMD64,
            "^windows ",
            [],
        ),
        (
            "darwin_amd64",
            "//platform:darwin_amd64",
            _DARWIN_AMD64,
            "^macos non-glibc",
            ["darwin_c"],
        ),
        (
            "darwin_arm64",
            "//platform:darwin_arm64",
            _DARWIN_ARM64,
            "^macos non-glibc",
            ["darwin_c"],
        ),
    ]
]

go_library(
    name = "c_test",
    srcs = ["c_test.go"],
    deps = [
        "@com_github_stretchr_testify//assert",
        "@rules_go//go/runfiles",
    ],
)
