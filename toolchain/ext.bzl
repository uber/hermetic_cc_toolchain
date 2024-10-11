load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

_COMMON_EXEC_PLATFORMS = [
    ("linux", "amd64"),
    ("linux", "arm64"),
    ("windows", "amd64"),
]

def _toolchains_impl(ctx):
    for os, arch in _COMMON_EXEC_PLATFORMS:
        zig_toolchains(exec = "{}-{}".format(os, arch))


    return ctx.extension_metadata(
        root_module_direct_deps= ["zig_sdk-{}-{}".format(os, arch) for os, arch in _COMMON_EXEC_PLATFORMS],
        root_module_direct_dev_deps=[],
        )


toolchains = module_extension(implementation = _toolchains_impl)
