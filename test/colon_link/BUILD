# Copyright 2025 Uber Technologies, Inc.
# Licensed under the MIT License

# Tests that Zig correctly handles the colon-link syntax ("-l :filename.so"),
# which links a library by exact filename.
#
# In Zig 0.14.0, this syntax was broken and the linker incorrectly reported:
#   ld.lld: error: unable to find library -l:mylib.so
#
# See https://github.com/ziglang/zig/issues/23287

load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")

# Build a shared library. Naming the cc_binary target "libgreeter.so" ensures
# the output file is named libgreeter.so (cc_binary uses the target name as-is).
cc_binary(
    name = "libgreeter.so",
    srcs = ["greeter.c"],
    linkshared = True,
    tags = ["manual"],
)

# Build a binary that links against libgreeter.so using the colon syntax.
# See https://github.com/ziglang/zig/issues/23287
cc_binary(
    name = "main",
    srcs = ["main.c"],
    # Make libgreeter.so available as a linker input so Bazel builds it
    # before the link step and includes it in the sandbox.
    additional_linker_inputs = [":libgreeter.so"],
    linkopts = [
        "-L$(BINDIR)/test/colon_link",
        "-l",
        ":libgreeter.so",
    ],
    tags = ["manual"],
)

# Only glibc targets are tested here. musl uses static linking by default,
# which is incompatible with dynamically linking a .so file.
[
    platform_binary(
        name = "main_{}".format(name),
        src = "main",
        platform = platform,
    )
    for name, platform in [
        ("linux_amd64_gnu.2.28", "//libc_aware/platform:linux_amd64_gnu.2.28"),
    ]
]
