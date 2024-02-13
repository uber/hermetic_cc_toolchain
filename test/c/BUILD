load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")

cc_binary(
    name = "which_libc",
    srcs = ["main.c"],
)

[
    (
        platform_binary(
            name = "which_libc_{}".format(name),
            src = "which_libc",
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
        ("linux_amd64_musl", "//libc_aware/platform:linux_amd64_musl", "linux non-glibc"),
        ("linux_amd64_gnu.2.28", "//libc_aware/platform:linux_amd64_gnu.2.28", "linux glibc_2.28"),
        ("linux_amd64", "//platform:linux_amd64", "linux glibc_2.28"),
    ]
]

[
    (
        platform_binary(
            name = "which_libc_{}".format(name),
            src = "which_libc",
            platform = platform,
            tags = tags,
        ),
    )
    for name, platform, tags in [
        (
            "darwin_amd64",
            "//platform:darwin_amd64",
            ["darwin_c"],
        ),
        (
            "darwin_arm64",
            "//platform:darwin_arm64",
            ["darwin_c"],
        ),
        ("windows_amd64", "//platform:windows_amd64", []),
        ("windows_arm64", "//platform:windows_arm64", []),
    ]
]
