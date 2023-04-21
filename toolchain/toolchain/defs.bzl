load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "target_structs")

def declare_toolchains():
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        # if the toolchain is libc aware, create two variants for it: one that
        # is only selected if libc is not expicitly set and another one that is
        # only selected if the specific libc variant is selected.
        extra_constraints = []
        if hasattr(target_config, "libc_constraint"):
            extra_constraints = ["@zig_sdk//libc:unconstrained"]

        _declare_toolchain(gotarget, zigtarget, target_config.constraint_values + extra_constraints)

def declare_libc_aware_toolchains():
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        # if the toolchain is libc aware, create two variants for it: one that
        # is only selected if libc is not expicitly set and another one that is
        # only selected if the specific libc variant is selected.
        if hasattr(target_config, "libc_constraint"):
            _declare_toolchain(gotarget, zigtarget, target_config.constraint_values + [target_config.libc_constraint])

def _declare_toolchain(gotarget, zigtarget, target_compatible_with):
    # register two kinds of toolchain targets: Go and Zig conventions.
    # Go convention: amd64/arm64, linux/darwin
    native.toolchain(
        name = gotarget,
        exec_compatible_with = None,
        target_compatible_with = target_compatible_with,
        toolchain = "@zig_sdk//:%s_cc" % zigtarget,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )

    # Zig convention: x86_64/aarch64, linux/macos
    native.toolchain(
        name = zigtarget,
        exec_compatible_with = None,
        target_compatible_with = target_compatible_with,
        toolchain = "@zig_sdk//:%s_cc" % zigtarget,
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )
