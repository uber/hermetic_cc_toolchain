load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

def _toolchains_impl(ctx):
    zig_toolchains()

toolchains = module_extension(implementation = _toolchains_impl)
