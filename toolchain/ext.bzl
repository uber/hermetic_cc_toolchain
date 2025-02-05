load("@bazel_features//:features.bzl", "bazel_features")
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

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return ctx.extension_metadata(
        root_module_direct_deps = ["zig_sdk"] + ["zig_sdk-{}-{}".format(os, arch) for os, arch in _COMMON_EXEC_PLATFORMS],
        root_module_direct_dev_deps = [],
        **metadata_kwargs
    )

toolchains = module_extension(implementation = _toolchains_impl)
