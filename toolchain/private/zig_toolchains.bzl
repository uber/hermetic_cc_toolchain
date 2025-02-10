ZigWrapperInfo = provider(
    doc = "Information about `zig` wrapper compiler.",
    fields = ["wrapper", "data"],
)

def declare_zig_toolchain(name):
    zig_wrapper_toolchain(
        name = name,
        wrapper = "//:tools/zig-wrapper",
        data = [
            "//:all",
        ],
    )

def _zig_wrapper_toolchain_impl(ctx):
    zig_toolchain_info = platform_common.ToolchainInfo(
        ziginfo = ZigWrapperInfo(
            wrapper = ctx.executable.wrapper,
            data = ctx.files.data,
        ),
    )
    return [zig_toolchain_info]

zig_wrapper_toolchain = rule(
    implementation = _zig_wrapper_toolchain_impl,
    attrs = {
        "wrapper": attr.label(
            executable = True,
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "data": attr.label_list(),
    },
)
