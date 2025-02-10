def _impl(ctx):
    zig_info = ctx.toolchains["@zig_sdk//toolchain:toolchain_type"].ziginfo
    dst = ctx.actions.declare_file(ctx.label.name)

    macos = ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]
    aarch64 = ctx.attr._aarch64_constraint[platform_common.ConstraintValueInfo]
    if ctx.target_platform_has_constraint(macos) and ctx.target_platform_has_constraint(aarch64):
        mcpu = "apple_a14"
    else:
        mcpu = "baseline"

    ctx.actions.run(
        inputs = [ctx.file.src],
        outputs = [dst],
        executable = zig_info.wrapper,
        tools = zig_info.data,
        arguments = [
            "build-exe",
            ctx.file.src.short_path,
            "-mcpu={}".format(mcpu),
            "-femit-bin={}".format(dst.path),
        ],
        mnemonic = "ZigBuildExe",
    )
    return [DefaultInfo(
        files = depset([dst]),
        executable = dst,
    )]

zig_binary = rule(
    implementation = _impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".zig"],
        ),
        "_macos_constraint": attr.label(
            default = "@platforms//os:macos",
        ),
        "_aarch64_constraint": attr.label(
            default = "@platforms//cpu:aarch64",
        ),
    },
    toolchains = ["@zig_sdk//toolchain:toolchain_type"],
    executable = True,
)
