def _impl(ctx):
    zig_info = ctx.toolchains["@zig_sdk//toolchain/zig:toolchain_type"].ziginfo
    dst = ctx.actions.declare_file(ctx.label.name)

    # Match the platform -> (target, mcpu) mapping used by the toolchain
    # (see toolchain/defs.bzl::_TARGET_MCPU) so the rule links against zig's
    # bundled hermetic libc stubs instead of the host SDK. Without an explicit
    # -target, zig 0.14.0 links against the host macOS SDK, whose libSystem.tbd
    # is unparseable on newer Xcode/SDKs (ziglang/zig#23324), yielding
    # undefined-symbol link errors.
    macos = ctx.attr._macos_constraint[platform_common.ConstraintValueInfo]
    linux = ctx.attr._linux_constraint[platform_common.ConstraintValueInfo]
    windows = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]
    aarch64 = ctx.attr._aarch64_constraint[platform_common.ConstraintValueInfo]

    if ctx.target_platform_has_constraint(macos):
        target = "aarch64-macos-none" if ctx.target_platform_has_constraint(aarch64) else "x86_64-macos-none"
        mcpu = "apple_a14" if ctx.target_platform_has_constraint(aarch64) else "baseline"
    elif ctx.target_platform_has_constraint(windows):
        target = "aarch64-windows-gnu" if ctx.target_platform_has_constraint(aarch64) else "x86_64-windows-gnu"
        mcpu = "baseline"
    else:
        # linux or anything else: use musl, which is fully hermetic
        target = "aarch64-linux-musl" if ctx.target_platform_has_constraint(aarch64) else "x86_64-linux-musl"
        mcpu = "baseline"

    ctx.actions.run(
        inputs = [ctx.file.src],
        outputs = [dst],
        executable = zig_info.zig,
        tools = zig_info.data,
        arguments = [
            "build-exe",
            ctx.file.src.short_path,
            "-target",
            target,
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
        "_linux_constraint": attr.label(
            default = "@platforms//os:linux",
        ),
        "_windows_constraint": attr.label(
            default = "@platforms//os:windows",
        ),
        "_aarch64_constraint": attr.label(
            default = "@platforms//cpu:aarch64",
        ),
    },
    toolchains = ["@zig_sdk//toolchain/zig:toolchain_type"],
    executable = True,
)
