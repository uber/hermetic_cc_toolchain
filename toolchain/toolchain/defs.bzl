load("@bazel-zig-cc//toolchain/private:defs.bzl", "DEFAULT_INCLUDE_DIRECTORIES", "ZIG_TOOL_PATH", "target_structs")

def declare_toolchains():
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        # register two kinds of toolchain targets: Go and Zig conventions.
        # Go convention: amd64/arm64, linux/darwin
        native.toolchain(
            name = gotarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = "@zig_sdk//private:%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )

        # Zig convention: x86_64/aarch64, linux/macos
        native.toolchain(
            name = zigtarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = "@zig_sdk//private:%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
