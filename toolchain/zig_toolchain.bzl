load("@hermetic_cc_toolchain//toolchain/private:zig_toolchain_info.bzl", "ZigToolchainInfo")

def _zig_toolchain_impl(ctx):
    zig_toolchain_info = platform_common.ToolchainInfo(
        ziginfo = ZigToolchainInfo(
            zig = ctx.executable.zig,
            data = ctx.files.data,
        ),
    )
    return [zig_toolchain_info]

zig_toolchain = rule(
    implementation = _zig_toolchain_impl,
    attrs = {
        "zig": attr.label(
            doc = "Zig compiler.",
            executable = True,
            mandatory = True,
            allow_single_file = True,
            cfg = "exec",
        ),
        "data": attr.label_list(
            doc = "List of any data needed by the toolchain.",
        ),
    },
)
