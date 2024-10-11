# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

def _platform_transition_impl(settings, attr):
    _ignore = settings
    return {
        "//command_line_option:platforms": "@zig_sdk-linux-amd64{}".format(attr.platform),
    }

_platform_transition = transition(
    implementation = _platform_transition_impl,
    inputs = [],
    outputs = [
        "//command_line_option:platforms",
    ],
)

def _platform_binary_impl(ctx):
    platform_sanitized = ctx.attr.platform.replace("/", "_").replace(":", "_")
    dstname = "{}-{}".format(
        _paths_basename(ctx.file.src.path),
        platform_sanitized,
    )
    dst = ctx.actions.declare_file(dstname)
    src = ctx.file.src
    ctx.actions.run(
        outputs = [dst],
        inputs = [src, ctx.file._cp],
        executable = ctx.file._cp.path,
        arguments = [src.path, dst.path],
    )
    return [DefaultInfo(
        files = depset([dst]),
        executable = dst,
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
    "_cp": attr.label(
        default = "//rules:cp",
        allow_single_file = True,
        cfg = "exec",
    ),
}

# wrap a single exectable and build it for the specified platform.
platform_binary = rule(
    implementation = _platform_binary_impl,
    cfg = _platform_transition,
    attrs = _attrs,
    executable = True,
)

## Copied from https://github.com/bazelbuild/bazel-skylib/blob/1.4.1/lib/paths.bzl#L22
def _paths_basename(p):
    return p.rpartition("/")[-1]
