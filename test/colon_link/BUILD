# Copyright 2025 Uber Technologies, Inc.
# Licensed under the MIT License

# Tests that Zig correctly handles the colon-link syntax ("-l:filename.so"),
# which links a library by exact filename. This is necessary when the library
# does not follow the standard "lib<name>.so" naming convention, making
# "-l<name>" insufficient.
#
# In Zig 0.14.0, this syntax was broken and the linker incorrectly reported:
#   ld.lld: error: unable to find library -l:mylib.so
#
# This is still broken as of Zig 0.16.0 and tracked upstream at:
# https://codeberg.org/ziglang/zig/issues/31823
#
# See https://github.com/ziglang/zig/issues/23287

load("@hermetic_cc_toolchain//rules:platform.bzl", "platform_binary")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")

# Build a versioned shared library "libgreeter.so.1". The standard "-lgreeter"
# flag looks for "libgreeter.so" (unversioned), so the colon syntax is required
# to link by exact filename.
cc_binary(
    name = "libgreeter.so.1",
    srcs = ["greeter.c"],
    linkshared = True,
    tags = ["manual"],
)

# Build a binary that links against libgreeter.so.1 using the colon syntax.
# "-lgreeter" would not work here since it looks for "libgreeter.so", not
# the versioned "libgreeter.so.1".
# See https://github.com/ziglang/zig/issues/23287
cc_binary(
    name = "main",
    srcs = ["main.c"],
    # Make libgreeter.so.1 available as a linker input so Bazel builds it
    # before the link step and includes it in the sandbox.
    additional_linker_inputs = [":libgreeter.so.1"],
    linkopts = [
        "-L$(BINDIR)/test/colon_link",
        "-l",
        ":libgreeter.so.1",
    ],
    tags = ["manual"],
)

# Only glibc targets are tested here. musl uses static linking by default,
# which is incompatible with dynamically linking a .so file.
# Tagged manual: colon-link is broken in Zig 0.16.0.
# Remove manual tag when upstream fix lands.
[
    platform_binary(
        name = "main_{}".format(name),
        src = "main",
        platform = platform,
        tags = ["manual"],
    )
    for name, platform in [
        ("linux_amd64_gnu.2.28", "//libc_aware/platform:linux_amd64_gnu.2.28"),
    ]
]
