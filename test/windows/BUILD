load("@bazel-zig-cc//rules:platform.bzl", "platform_binary", "platform_test")

cc_binary(
    name = "winver",
    srcs = ["main.c"],
    tags = ["manual"],
)

platform_test(
    name = "winver_windows_amd64",
    src = "winver",
    platform = "//platform:windows_amd64",
    run_under = "wine64-stable",
    tags = ["no-sandbox"],
)

platform_binary(
    name = "winver_windows_arm64",
    src = "winver",
    platform = "//platform:windows_arm64",
)
