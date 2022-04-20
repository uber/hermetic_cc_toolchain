def _platform_transition_impl(settings, attr):
    _ignore = settings
    return {
        "//command_line_option:platforms": "@zig_sdk{}".format(attr.platform),
    }

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
    ],
)

def _platform_binary_impl(ctx):
    source_info = ctx.attr.src[DefaultInfo]

    executable = None
    if source_info.files_to_run and source_info.files_to_run.executable:
        executable = ctx.actions.declare_file("{}_{}".format(ctx.file.src.basename, ctx.attr.platform))
        ctx.actions.run_shell(
            command = "cp {} {}".format(source_info.files_to_run.executable.path, executable.path),
            inputs = [source_info.files_to_run.executable],
            outputs = [executable],
        )

    return [DefaultInfo(
        files = depset(ctx.files.src),
        executable = executable,
    )]

_attrs = {
    "src": attr.label(
        allow_single_file = True,
        mandatory = True,
        doc = "Target to build.",
    ),
    "platform": attr.string(
        doc = "The platform to build the target for.",
    ),
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}

# wrap a single exectable and build it for the specified platform.
platform_binary = rule(
    implementation = _platform_binary_impl,
    cfg = _platform_transition,
    attrs = _attrs,
    executable = True,
)

# wrap a single test target and build it for the specified platform.
platform_test = rule(
    implementation = _platform_binary_impl,
    cfg = _platform_transition,
    attrs = _attrs,
    test = True,
)
