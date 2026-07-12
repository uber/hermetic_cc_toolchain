def _impl(ctx):
    zig_info = ctx.toolchains["@zig_sdk//toolchain/zig:toolchain_type"].ziginfo
    dst = ctx.actions.declare_file(ctx.label.name)

    # On macOS, pass an explicit -target so zig links against its bundled
    # hermetic libc stubs instead of the host SDK. Without it, zig 0.14.0
    # links against the host macOS SDK, whose libSystem.tbd is unparseable
    # on newer Xcode/SDKs (ziglang/zig#23324), yielding undefined-symbol
    # link errors. Other platforms build natively as before: Linux glibc
    # detection works, and on Windows zig bundles the mingw-w64 libc.
    macos = ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]
    aarch64 = ctx.attr._aarch64_constraint[platform_common.ConstraintValueInfo]

    target_args = []
    if ctx.target_platform_has_constraint(macos):
        if ctx.target_platform_has_constraint(aarch64):
            target_args = ["-target", "aarch64-macos-none"]
            mcpu = "apple_a14"
        else:
            target_args = ["-target", "x86_64-macos-none"]
            mcpu = "baseline"
    else:
        mcpu = "baseline"

    ctx.actions.run(
        inputs = [ctx.file.src],
        outputs = [dst],
        executable = zig_info.zig,
        tools = zig_info.data,
        arguments = [
            "build-exe",
            ctx.file.src.short_path,
        ] + target_args + [
            "-mcpu={}".format(mcpu),
            "-femit-bin={}".format(dst.path),
            "-lc",
        ],
        mnemonic = "ZigBuildExe",
        toolchain = "@zig_sdk//toolchain/zig:toolchain_type",
        progress_message = "Compiling '%{input}' to create '%{output}'",
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
    toolchains = ["@zig_sdk//toolchain/zig:toolchain_type"],
    executable = True,
)
