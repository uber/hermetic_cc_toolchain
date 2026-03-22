# Copyright 2025 Uber Technologies, Inc.
# Licensed under the MIT License

# Tests that Zig correctly handles the "-l :filename.so" linking syntax
# (with a space between -l and :filename).
#
# In Zig 0.14.0, the linker incorrectly reported:
#   ld.lld: error: unable to find library -l:mylib.so
# when "-l" and ":mylib.so" were passed as two separate arguments.
#
# Bazel shell-tokenizes linkopts strings, so the entry "-l :libgreeter.so"
# is split into two tokens ("-l" and ":libgreeter.so") before being passed
# to the linker — reproducing exactly the form that Zig 0.14.0 mishandled.
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
# The linkopts string "-l :libgreeter.so" is shell-tokenized by Bazel into
# the two tokens "-l" and ":libgreeter.so", which is the exact invocation
# form that Zig 0.14.0 failed to handle.
# See https://github.com/ziglang/zig/issues/23287
cc_binary(
    name = "main",
    srcs = ["main.c"],
    # Make libgreeter.so available as a linker input so Bazel builds it
    # before the link step and includes it in the sandbox.
    additional_linker_inputs = [":libgreeter.so"],
    linkopts = [
        # Add the output directory to the library search path.
        "-L$(BINDIR)/test/colon_link",
        # Link using the colon syntax. Bazel tokenizes this into:
        #   ["-l", ":libgreeter.so"]
        # testing the space-separated form from the Zig issue.
        "-l :libgreeter.so",
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
