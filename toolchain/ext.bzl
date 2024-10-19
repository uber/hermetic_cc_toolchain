load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

_HOSTS = (
    "amd64-linux",
    "aarch64-linux",
)

def _toolchains_impl(ctx):
    for EXEC_HOST in _HOSTS:
        zig_toolchains(exec = EXEC_HOST)


    return ctx.extension_metadata(
        root_module_direct_deps= ["{}-zig_sdk".format(h) for h in _HOSTS],
        root_module_direct_dev_deps=[],
        )


toolchains = module_extension(implementation = _toolchains_impl)
