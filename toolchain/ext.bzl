load("@hermetic_cc_toolchain//toolchain:defs.bzl", "host_zig_repository", zig_toolchains = "toolchains")

_COMMON_EXEC_PLATFORMS = [
    ("linux", "amd64"),
    ("linux", "arm64"),
    ("windows", "amd64"),
    ("macos", "arm64"),
    ("macos", "amd64"),
]

def _toolchains_impl(ctx):
    for os, arch in _COMMON_EXEC_PLATFORMS:
        zig_toolchains(exec_os = os, exec_arch = arch)

    host_zig_repository(name = "zig_sdk")
    return ctx.extension_metadata(
        root_module_direct_deps = ["zig_sdk"] + ["zig_sdk-{}-{}".format(os, arch) for os, arch in _COMMON_EXEC_PLATFORMS],
        root_module_direct_dev_deps = [],
    )

toolchains = module_extension(implementation = _toolchains_impl)
