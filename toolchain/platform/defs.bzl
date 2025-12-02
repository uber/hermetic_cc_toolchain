load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "LIBCS")

_CPUS = (("x86_64", "amd64"), ("aarch64", "arm64"))
_OS = {
    "linux": ["linux"],
    "macos": ["macos", "darwin"],
    "windows": ["windows"],
}

def declare_platforms():
    # create @zig_sdk//{os}_{arch}_platform entries with zig and go conventions
    for zigcpu, gocpu in _CPUS:
        for bzlos, oss in _OS.items():
            for os in oss:
                declare_platform(gocpu, zigcpu, bzlos, os)

    # We can support GOARCH=wasm32 after https://github.com/golang/go/issues/63131
    declare_platform("wasm", "wasm32", "wasi", "wasip1")
    declare_platform("wasm", "wasm32", "none", "none")

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
                extra_constraints = ["//libc:{}".format(libc)],
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
