load("@bazel_features//:features.bzl", "bazel_features")
load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

_COMMON_EXEC_PLATFORMS = {
    "linux": ["amd64", "arm64"],
    "macos": ["amd64", "arm64"],
    "windows": ["amd64"],
}

def _toolchains_impl(ctx):
    repos = zig_toolchains(exec_platforms = _COMMON_EXEC_PLATFORMS)

    metadata_kwargs = {}
    if bazel_features.external_deps.extension_metadata_has_reproducible:
        metadata_kwargs["reproducible"] = True

    return ctx.extension_metadata(
        root_module_direct_deps = repos.direct,
        root_module_direct_dev_deps = [],
        **metadata_kwargs
    )

toolchains = module_extension(implementation = _toolchains_impl)
