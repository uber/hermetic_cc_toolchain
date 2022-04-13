load("@bazel-zig-cc//toolchain/private:defs.bzl", "LIBCS")

def declare_libcs():
    for libc in LIBCS:
        native.constraint_value(
            name = libc,
            constraint_setting = "variant",
        )
