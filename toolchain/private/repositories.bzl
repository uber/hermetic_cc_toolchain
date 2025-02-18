load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "transform_arch_name", "transform_os_name")

def _define_zig_toolchains(repository_ctx, os, arch):
    _os = transform_os_name(os)
    _arch = transform_arch_name(arch)

    # TODO: find better way for `configs` & `package`
    configs = "@zig_config-{}-{}".format(_os, _arch)
    package = "{}-{}/".format(_os, _arch)

    if _os == "HOST" and _arch == "HOST":
        configs = "@zig_config"
        package = ""

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
alias(
    name = "zig",
    actual = "{}//:zig",
)
""".format("@zig_config" if repository_ctx.attr.host_only else "@zig_config-{}-{}".format(_os, _arch))

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

    # if empty get host os & arch
    if not bool(repository_ctx.attr.exec_platforms):
        _define_zig_toolchains(repository_ctx, "HOST", "HOST")
        return

    for os, archs in repository_ctx.attr.exec_platforms.items():
        for arch in archs:
            _define_zig_toolchains(repository_ctx, os, arch)

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
