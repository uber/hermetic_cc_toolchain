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
            env = {"QEMU_LD_PREFIX": "/usr/aarch64-linux-gnu"} if is_arm64 else {},
            platform = platform,
            run_under = "qemu-aarch64-static" if is_arm64 else "",
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
    for name, platform, want, is_arm64 in [
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl", "non-glibc", False),
        ("linux_amd64_gnu.2.19", "//libc_aware/platform:linux_amd64_gnu.2.19", "glibc_2.19", False),
        ("linux_amd64_gnu.2.28", "//libc_aware/platform:linux_amd64_gnu.2.28", "glibc_2.28", False),
        ("linux_amd64", "//platform:linux_amd64", "glibc_2.19", False),
        ("linux_arm64", "//platform:linux_arm64", "glibc_2.28", True),
    ]
]
