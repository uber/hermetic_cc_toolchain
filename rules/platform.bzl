# Copyright 2023 Uber Technologies, Inc.
# Licensed under the Apache License, Version 2.0

load("@bazel_skylib//lib:paths.bzl", "paths")

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
    platform_sanitized = ctx.attr.platform.replace("/", "_").replace(":", "_")
    dst = ctx.actions.declare_file("{}-{}".format(paths.basename(ctx.file.src.path), platform_sanitized))
    src = ctx.file.src
    ctx.actions.run(
        outputs = [dst],
        inputs = [src],
        executable = "cp",
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
