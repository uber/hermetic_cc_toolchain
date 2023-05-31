def _impl(ctx):
    dst = ctx.actions.declare_file(ctx.label.name)

    macos = ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]
    aarch64 = ctx.attr._aarch64_constraint[platform_common.ConstraintValueInfo]
    if ctx.target_platform_has_constraint(macos) and ctx.target_platform_has_constraint(aarch64):
        mcpu = "apple_a14"
    else:
        mcpu = "baseline"

    ctx.actions.run(
        inputs = [ctx.file.src] + ctx.files._zig_sdk,
        outputs = [dst],
        executable = ctx.file._zig.path,
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
        "_zig": attr.label(
            default = "@zig_sdk//:tools/zig-wrapper",
            allow_single_file = True,
        ),
        "_zig_sdk": attr.label(
            default = "@zig_sdk//:all",
            allow_files = True,
        ),
        "_macos_constraint": attr.label(
            default = "@platforms//os:macos",
        ),
        "_aarch64_constraint": attr.label(
            default = "@platforms//cpu:aarch64",
        ),
    },
    executable = True,
)
