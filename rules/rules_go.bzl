load("@io_bazel_rules_go//go:def.bzl", go_binary_rule = "go_binary")

"""
go_binary overrides go_binary from rules_go and provides default
gc_linkopts values that are needed to compile for macos target.
To use it, add this map_kind gazelle directive to your BUILD.bazel files
where target binary needs to be compiled with zig toolchain.

Example: if this toolchain is registered as bazel-zig-cc in your WORKSPACE, add this to
your root BUILD file
# gazelle:map_kind go_binary go_binary @bazel-zig-cc//rules:rules_go.bzl
"""

_MACOS_GC_LINKOPTS = ["-s", "-w", "-buildmode=pie"]

def go_binary(**kwargs):
    kwargs["gc_linkopts"] = select({
        "@platforms//os:macos": _MACOS_GC_LINKOPTS,
        "//conditions:default": [],
    }) + kwargs.pop("gc_linkopts", [])
    go_binary_rule(**kwargs)
