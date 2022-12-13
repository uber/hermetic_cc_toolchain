_ZIG_TOOL_PATH = "tools/{zigtarget}/{zig_tool}"

# Zig supports even older glibcs than defined below, but we have tested only
# down to 2.17.
# $ zig targets | jq -r '.glibc[]' | sort -V
_GLIBCS = [
    "2.17",
    "2.18",
    "2.19",
    "2.22",
    "2.23",
    "2.24",
    "2.25",
    "2.26",
    "2.27",
    "2.28",
    "2.29",
    "2.30",
    "2.31",
    "2.32",
    "2.33",
    "2.34",
]

LIBCS = ["musl"] + ["gnu.{}".format(glibc) for glibc in _GLIBCS]

def zig_tool_path(os):
    if os == "windows":
        return _ZIG_TOOL_PATH + ".bat"
    else:
        return _ZIG_TOOL_PATH

def target_structs():
    ret = []
    for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64")):
        ret.append(_target_darwin(gocpu, zigcpu))
        ret.append(_target_windows(gocpu, zigcpu))
        ret.append(_target_linux_musl(gocpu, zigcpu))
        for glibc in _GLIBCS:
            ret.append(_target_linux_gnu(gocpu, zigcpu, glibc))
    return ret

def _target_darwin(gocpu, zigcpu):
    min_os = "11"
    return struct(
        gotarget = "darwin_{}".format(gocpu),
        zigtarget = "{}-macos-none".format(zigcpu),
        includes = [
            "libunwind/include",
            # TODO: Define a toolchain for each minimum OS version
            "libc/include/{}-macos.{}-none".format(zigcpu, min_os),
            "libc/include/any-macos.{}-any".format(min_os),
            "libc/include/any-macos-any",
            "include",
        ],
        dynamic_library_linkopts = ["-Wl,-undefined=dynamic_lookup"],
        copts = [],
        libc = "darwin",
        bazel_target_cpu = "darwin",
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld64.lld"},
    )

def _target_windows(gocpu, zigcpu):
    return struct(
        gotarget = "windows_{}".format(gocpu),
        zigtarget = "{}-windows-gnu".format(zigcpu),
        includes = [
            "libc/mingw",
            "libunwind/include",
            "libc/include/any-windows-any",
            "include",
        ],
        dynamic_library_linkopts = [],
        copts = [],
        libc = "mingw",
        bazel_target_cpu = "x64_windows",
        constraint_values = [
            "@platforms//os:windows",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld64.lld"},
    )

def _target_linux_gnu(gocpu, zigcpu, glibc_version):
    glibc_suffix = "gnu.{}".format(glibc_version)

    # https://github.com/ziglang/zig/issues/5882#issuecomment-888250676
    # fcntl_hack is only required for glibc 2.27 or less.
    fcntl_hack = glibc_version < "2.28"

    return struct(
        gotarget = "linux_{}_{}".format(gocpu, glibc_suffix),
        zigtarget = "{}-linux-{}".format(zigcpu, glibc_suffix),
        includes = [
                       "libc/include/{}-linux-gnu".format(zigcpu),
                       "libc/include/generic-glibc",
                   ] +
                   # x86_64-linux-any is x86_64-linux and x86-linux combined.
                   (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []) +
                   (["libc/include/{}-linux-any".format(zigcpu)] if zigcpu != "x86_64" else []) + [
            "libc/include/any-linux-any",
            "include",
        ],
        toplevel_include = ["glibc-hacks"] if fcntl_hack else [],
        compiler_extra_includes = ["glibc-hacks/glibchack-fcntl.h"] if fcntl_hack else [],
        linker_version_scripts = ["glibc-hacks/fcntl.map"] if fcntl_hack else [],
        dynamic_library_linkopts = [],
        copts = [],
        libc = "glibc",
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        libc_constraint = "@zig_sdk//libc:{}".format(glibc_suffix),
        tool_paths = {"ld": "ld.lld"},
    )

def _target_linux_musl(gocpu, zigcpu):
    return struct(
        gotarget = "linux_{}_musl".format(gocpu),
        zigtarget = "{}-linux-musl".format(zigcpu),
        includes = [
                       "libc/include/{}-linux-musl".format(zigcpu),
                       "libc/include/generic-musl",
                   ] +
                   # x86_64-linux-any is x86_64-linux and x86-linux combined.
                   (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []) +
                   (["libc/include/{}-linux-any".format(zigcpu)] if zigcpu != "x86_64" else []) + [
            "libc/include/any-linux-any",
            "include",
        ],
        dynamic_library_linkopts = [],
        copts = ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        libc = "musl",
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        libc_constraint = "@zig_sdk//libc:musl",
        tool_paths = {"ld": "ld.lld"},
    )
