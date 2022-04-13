load("@bazel-zig-cc//rules:platform.bzl", "platform_binary")

cc_binary(
    name = "which_libc",
    srcs = ["main.c"],
    target_compatible_with = [
        "@platforms//os:linux",
    ],
)

[
    (
        platform_binary(
            name = "which_libc_{}".format(name),
            src = "which_libc",
            extra_toolchains = [
                # toolchains for specific libc versions
                "//libc_aware/toolchain:linux_amd64_gnu.2.19",
                "//libc_aware/toolchain:linux_amd64_gnu.2.28",
                "//libc_aware/toolchain:linux_amd64_gnu.2.31",
                "//libc_aware/toolchain:linux_amd64_musl",
                # fallback toolchains
                "//toolchain:linux_amd64_gnu.2.19",
                "//toolchain:linux_arm64_gnu.2.28",
            ],
            platform = platform,
        ),
        sh_test(
            name = "test_libc_{}".format(name),
            srcs = ["test.sh"],
            data = ["which_libc_{}".format(name)],
            env = {
                "WANT": want,
                "BINARY": "$(location which_libc_{})".format(name),
            },
        ),
    )
    for name, platform, want in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl", "non-glibc"),
        ("linux_amd64_gnu.2.19", "//libc_aware/platform:linux_amd64_gnu.2.19", "glibc_2.19"),
        ("linux_amd64_gnu.2.28", "//libc_aware/platform:linux_amd64_gnu.2.28", "glibc_2.28"),
        ("linux_amd64_gnu.2.31", "//libc_aware/platform:linux_amd64_gnu.2.31", "glibc_2.31"),
        ("linux_amd64", "//platform:linux_amd64", "glibc_2.19"),
        ("linux_arm64", "//platform:linux_arm64", "glibc_2.28"),
    ]
]
