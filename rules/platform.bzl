def _vars_script(env, run_under, cmd):
    ret = ["#!/bin/sh"]
    for k, v in env.items():
        ret += ['export {}="{}"'.format(k, v)]
    ret += ['exec {} {} "$@"'.format(run_under, cmd)]
    return "\n".join(ret) + "\n"  # trailing newline is easier on the eyes

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
        command = _vars_script(ctx.attr.env, ctx.attr.run_under, source_info.files_to_run.executable.short_path)
        executable = ctx.actions.declare_file("{}_{}".format(ctx.file.src.basename, ctx.attr.platform))
        ctx.actions.write(
            output = executable,
            content = command,
            is_executable = True,
        )

    return [DefaultInfo(
        executable = executable,
        files = depset([executable]),
        runfiles = ctx.runfiles(files = ctx.files.src),
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
    "run_under": attr.string(
        doc = "wrapper executable",
    ),
    "env": attr.string_dict(
        doc = "Environment variables for the test",
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
