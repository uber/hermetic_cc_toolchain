load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "transform_arch_name", "transform_os_name")

def _define_zig_toolchains(repository_ctx, configs, package = ""):
    repository_ctx.template(
        "toolchain/{}BUILD".format(package),
        Label("//toolchain/toolchain:BUILD.bazel.tmpl"),
        executable = False,
        substitutions = {
            "{configs}": repr(configs),
        },
    )

    repository_ctx.template(
        "libc_aware/toolchain/{}BUILD".format(package),
        Label("//toolchain/libc_aware/toolchain:BUILD.bazel.tmpl"),
        executable = False,
        substitutions = {
            "{configs}": repr(configs),
        },
    )

def _zig_sdk_repository_impl(repository_ctx):
    _os = transform_os_name(repository_ctx.os.name)
    _arch = transform_arch_name(repository_ctx.os.arch)

    _toolchain_type = """
package(
    default_visibility = ["//visibility:public"],
)

toolchain_type(
    name = "toolchain_type",
)
"""
    _build = """
package(
    default_visibility = ["//visibility:public"],
)

alias(
    name = "zig",
    actual = "@zig_config//:zig",
)
"""

    repository_ctx.file(
        "BUILD.bazel",
        _build,
    )
    repository_ctx.file(
        "toolchain/zig/BUILD.bazel",
        _toolchain_type,
    )
    repository_ctx.file(
        "libc/BUILD.bazel",
        repository_ctx.read(Label("//toolchain/libc:BUILD")),
    )
    repository_ctx.file(
        "platform/BUILD.bazel",
        repository_ctx.read(Label("//toolchain/platform:BUILD")),
    )
    repository_ctx.file(
        "libc_aware/platform/BUILD.bazel",
        repository_ctx.read(Label("//toolchain/libc_aware/platform:BUILD")),
    )

    # toolchains for the HOST
    _define_zig_toolchains(repository_ctx, "@zig_config")

    # Remove the HOST to not duplicate Zig HOST toolchains (@zig_config)
    exec_platforms = repository_ctx.attr.exec_platforms

    _archs = exec_platforms.get(_os, list())
    if _arch in _archs:
        _archs.remove(_arch)
        exec_platforms[_os] = _archs

    for os, archs in exec_platforms.items():
        for arch in archs:
            _os = transform_os_name(os)
            _arch = transform_arch_name(arch)
            configs = "@zig_config-{}-{}".format(_os, _arch)
            package = "{}-{}/".format(_os, _arch)

            _define_zig_toolchains(repository_ctx, configs, package = package)

zig_sdk_repository = repository_rule(
    doc = "Creates common constraint & platform definitions.",
    attrs = {
        "host_only": attr.bool(
            default = False,
        ),
        "exec_platforms": attr.string_list_dict(
            doc = "Dictionary, where the keys are oses and the values are lists of supported architectures",
            mandatory = True,
        ),
    },
    implementation = _zig_sdk_repository_impl,
)
