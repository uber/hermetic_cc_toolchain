def _impl(ctx):
    dst = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.run(
        inputs = [ctx.file.src] + ctx.files._zig_sdk,
        outputs = [dst],
        executable = ctx.file._zig.path,
        arguments = [
            "build-exe",
            ctx.file.src.short_path,
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
    },
    executable = True,
)
