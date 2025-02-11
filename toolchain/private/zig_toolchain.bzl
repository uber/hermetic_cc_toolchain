load("@hermetic_cc_toolchain//toolchain:zig_toolchain.bzl", "zig_toolchain")

def declare_zig_toolchain(name):
    zig_toolchain(
        name = name,
        zig = "//:tools/zig-wrapper",
        data = [
            "//:all",
        ],
    )
