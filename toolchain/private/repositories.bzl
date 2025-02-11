load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "transform_arch_name", "transform_os_name")

# Platforms & constraints repository
def _zig_sdk_repository_impl(repository_ctx):
    toolchain_type = """
package(
    default_visibility = ["//visibility:public"],
)
toolchain_type(
    name = "toolchain_type",
)
"""

    repository_ctx.file(
        "BUILD.bazel",
        "# main BUILD.bazel file\n",
    )
    repository_ctx.file(
        "toolchain/BUILD.bazel",
        toolchain_type,
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

zig_sdk_repository = repository_rule(
    doc = "Creates common constraint & platform definitions.",
    implementation = _zig_sdk_repository_impl,
)

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
        "{}toolchain/BUILD".format(package),
        Label("//toolchain/toolchain:BUILD.bazel.tmpl"),
        executable = False,
        substitutions = {
            "{configs}": repr(configs),
        },
    )

    repository_ctx.template(
        "{}libc_aware/toolchain/BUILD".format(package),
        Label("//toolchain/libc_aware/toolchain:BUILD.bazel.tmpl"),
        executable = False,
        substitutions = {
            "{configs}": repr(configs),
        },
    )

# Toolchains repository
def _zig_toolchains_repository_impl(repository_ctx):
    repository_ctx.file("BUILD.bazel", "# main BUILD.bazel file\n")

    # if empty get host os & arch
    if not bool(repository_ctx.attr.exec_platforms):
        _define_zig_toolchains(repository_ctx, "HOST", "HOST")
        return

    for os, archs in repository_ctx.attr.exec_platforms.items():
        for arch in archs:
            _define_zig_toolchains(repository_ctx, os, arch)

zig_toolchains_repository = repository_rule(
    doc = "Creates toolchain definitions based on provided configs.",
    attrs = {
        "exec_platforms": attr.string_list_dict(
            doc = "Dictionary, where the keys are oses and the values are lists of supported architectures",
            mandatory = True,
        ),
    },
    implementation = _zig_toolchains_repository_impl,
)
