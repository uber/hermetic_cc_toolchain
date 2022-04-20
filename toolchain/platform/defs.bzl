load("@bazel-zig-cc//toolchain/private:defs.bzl", "LIBCS")

_CPUS = (("x86_64", "amd64"), ("aarch64", "arm64"))

def declare_platforms():
    # create @zig_sdk//{os}_{arch}_platform entries with zig and go conventions
    for zigcpu, gocpu in _CPUS:
        for bzlos, oss in {"linux": ["linux"], "macos": ["macos", "darwin"]}.items():
            for os in oss:
                declare_platform(gocpu, zigcpu, bzlos, os)

def declare_libc_aware_platforms():
    # create @zig_sdk//{os}_{arch}_platform entries with zig and go conventions
    # with libc specified
    for zigcpu, gocpu in _CPUS:
        for libc in LIBCS:
            declare_platform(
                gocpu,
                zigcpu,
                "linux",
                "linux",
                suffix = "_{}".format(libc),
                extra_constraints = ["@zig_sdk//libc:{}".format(libc)],
            )

def declare_platform(gocpu, zigcpu, bzlos, os, suffix = "", extra_constraints = []):
    constraint_values = [
        "@platforms//os:{}".format(bzlos),
        "@platforms//cpu:{}".format(zigcpu),
    ] + extra_constraints

    native.platform(
        name = "{os}_{zigcpu}{suffix}".format(os = os, zigcpu = zigcpu, suffix = suffix),
        constraint_values = constraint_values,
    )

    native.platform(
        name = "{os}_{gocpu}{suffix}".format(os = os, gocpu = gocpu, suffix = suffix),
        constraint_values = constraint_values,
    )
