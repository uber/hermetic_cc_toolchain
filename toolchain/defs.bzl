load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(":zig_toolchain.bzl", "zig_cc_toolchain_config")

DEFAULT_TOOL_PATHS = {
    "ar": "ar",
    "gcc": "c++",  # https://github.com/bazelbuild/bazel/issues/4644
    "cpp": "/usr/bin/false",
    "gcov": "/usr/bin/false",
    "nm": "/usr/bin/false",
    "objdump": "/usr/bin/false",
    "strip": "/usr/bin/false",
}.items()

DEFAULT_INCLUDE_DIRECTORIES = [
    "include",
    "libcxx/include",
    "libcxxabi/include",
]

# https://github.com/ziglang/zig/issues/5882#issuecomment-888250676
# only required for glibc 2.27 or less.
_fcntl_map = """
GLIBC_2.2.5 {
   fcntl;
};
"""
_fcntl_h = """__asm__(".symver fcntl64, fcntl@GLIBC_2.2.5");\n"""

# Zig supports even older glibcs than defined below, but we have tested only
# down to 2.19, which is in Debian Jessie.
_GLIBCS = [
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
]

def _target_darwin(gocpu, zigcpu):
    return struct(
        gotarget = "darwin_{}".format(gocpu),
        zigtarget = "{}-macos-gnu".format(zigcpu),
        includes = [
            "libunwind/include",
            "libc/include/any-macos-any",
            "libc/include/{}-macos-any".format(zigcpu),
            "libc/include/{}-macos-gnu".format(zigcpu),
        ],
        linkopts = [],
        copts = [],
        bazel_target_cpu = "darwin",
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld64.lld"},
    )

def _target_linux_gnu(gocpu, zigcpu, glibc_version):
    return struct(
        gotarget = "linux_{}_gnu".format(gocpu),
        zigtarget = "{}-linux-gnu".format(zigcpu),
        target_suffix = ".{}".format(glibc_version),
        includes = [
            "libunwind/include",
            "libc/include/generic-glibc",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-gnu".format(zigcpu),
            "libc/include/{}-linux-any".format(zigcpu),
        ],
        linker_version_script = "glibc-hacks/fcntl.map" if glibc_version < "2.28" else None,
        compiler_extra_include = "glibchack-fcntl.h" if glibc_version < "2.28" else None,
        linkopts = ["-lc++", "-lc++abi"],
        copts = [],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld.lld"},
    )

def _target_linux_musl(gocpu, zigcpu):
    return struct(
        gotarget = "linux_{}_musl".format(gocpu),
        zigtarget = "{}-linux-musl".format(zigcpu),
        includes = [
            "libc/include/generic-musl",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-musl".format(zigcpu),
            "libc/include/{}-linux-any".format(zigcpu),
        ],
        linkopts = ["-s", "-w"],
        copts = ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld.lld"},
    )

def register_toolchains(
        register_linux_libc = "gnu",
        glibc_version = _GLIBCS[-1],
        speed_first_safety_later = False):
    """register_toolchains downloads and registers zig toolchains:

        @param register_linux_libc: either "musl" or "gnu". Only one can be
            registered at a time to avoid conflict.
        @param glibc_version: which glibc version to use when compiling via
            glibc (either via registered toolchain, or via --extra_toolchains).
        @param speed_first_safety_later: remove workaround of
            github.com/ziglang/zig/issues/9431; dramatically increases compilation
            speed
    """

    if register_linux_libc not in ("gnu", "musl"):
        fail("register_linux_libc must be either gnu or musl")

    zig_repository(
        name = "zig_sdk",
        # Pre-release:
        version = "0.9.0-dev.727+aad459836",
        url_format = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz",
        # Release:
        # version = "0.8.0",
        # url_format = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz",
        host_platform_sha256 = {
            "linux-x86_64": "1a0f45e77e2323d4afb3405868c0d96a88170a922eb60fc06f233ac8395fbfd5",
            "macos-x86_64": "cdc76afd3e361c8e217e4d56f2027ec6482d7f612462c27794149b7ad31b9244",
        },
        host_platform_include_root = {
            "macos-x86_64": "lib/zig/",
            "linux-x86_64": "lib/",
        },
        glibc_version = glibc_version,
        speed_first_safety_later = speed_first_safety_later,
    )

    for cfg in _target_structs(glibc_version):
        if cfg.gotarget.startswith("linux"):
            if not cfg.gotarget.endswith(register_linux_libc):
                continue

        native.register_toolchains(
            "@zig_sdk//:%s_toolchain" % cfg.gotarget,
        )

ZIG_TOOL_PATH = "tools/{zig_tool}"
ZIG_TOOL_WRAPPER = """#!/bin/bash
if [[ -n "$TMPDIR" ]]; then
  cache_prefix=$TMPDIR
else
  cache_prefix="$HOME/.cache"
  if [[ "$(uname)" = Darwin ]]; then
    cache_prefix="$HOME/Library/Caches"
  fi
fi
export ZIG_LOCAL_CACHE_DIR="$cache_prefix/bazel-zig-cc"
export ZIG_GLOBAL_CACHE_DIR=$ZIG_LOCAL_CACHE_DIR

# https://github.com/ziglang/zig/issues/9431
exec {maybe_flock} "{zig}" "{zig_tool}" "$@"
"""

_ZIG_TOOLS = [
    "c++",
    "cc",
    "ar",
    "ld.lld",  # ELF
    "ld64.lld",  # Mach-O
    "lld-link",  # COFF
    "wasm-ld",  # WebAssembly
]

def _zig_repository_impl(repository_ctx):
    if repository_ctx.os.name.lower().startswith("mac os"):
        host_platform = "macos-x86_64"
    else:
        host_platform = "linux-x86_64"

    zig_include_root = repository_ctx.attr.host_platform_include_root[host_platform]
    zig_sha256 = repository_ctx.attr.host_platform_sha256[host_platform]
    format_vars = {
        "version": repository_ctx.attr.version,
        "host_platform": host_platform,
    }
    zig_url = repository_ctx.attr.url_format.format(**format_vars)

    repository_ctx.download_and_extract(
        url = zig_url,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = zig_sha256,
    )

    maybe_flock = "flock"
    if repository_ctx.attr.speed_first_safety_later:
        maybe_flock = ""

    for zig_tool in _ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool = zig_tool),
            ZIG_TOOL_WRAPPER.format(
                zig = str(repository_ctx.path("zig")),
                zig_tool = zig_tool,
                maybe_flock = maybe_flock,
            ),
        )

    repository_ctx.file(
        "glibc-hacks/fcntl.map",
        content = _fcntl_map,
    )
    repository_ctx.file(
        "glibc-hacks/glibchack-fcntl.h",
        content = _fcntl_h,
    )

    repository_ctx.template(
        "BUILD.bazel",
        Label("//toolchain:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{absolute_path}": shell.quote(str(repository_ctx.path(""))),
            "{zig_include_root}": shell.quote(zig_include_root),
            "{glibc_version}": shell.quote(repository_ctx.attr.glibc_version),
        },
    )

zig_repository = repository_rule(
    attrs = {
        "version": attr.string(),
        "host_platform_sha256": attr.string_dict(),
        "url_format": attr.string(),
        "host_platform_include_root": attr.string_dict(),
        "glibc_version": attr.string(values = _GLIBCS),
        "speed_first_safety_later": attr.bool(),
    },
    implementation = _zig_repository_impl,
)

def _target_structs(glibc_version):
    ret = []
    for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64")):
        ret.append(_target_darwin(gocpu, zigcpu))
        ret.append(_target_linux_gnu(gocpu, zigcpu, glibc_version))
        ret.append(_target_linux_musl(gocpu, zigcpu))
    return ret

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def zig_build_macro(absolute_path, zig_include_root, glibc_version):
    filegroup(name = "empty")
    native.exports_files(["zig"], visibility = ["//visibility:public"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in _target_structs(glibc_version):
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget
        native.platform(
            name = gotarget,
            constraint_values = target_config.constraint_values,
        )

        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))
            cxx_builtin_include_directories.append(absolute_path + "/" + d)

        absolute_tool_paths = {}
        for name, path in target_config.tool_paths.items() + DEFAULT_TOOL_PATHS:
            if path[0] == "/":
                absolute_tool_paths[name] = path
                continue
            tool_path = ZIG_TOOL_PATH.format(zig_tool = path)
            absolute_tool_paths[name] = "%s/%s" % (absolute_path, tool_path)

        linkopts = target_config.linkopts
        copts = target_config.copts
        compiler_extra_include = getattr(target_config, "compiler_extra_include", "")
        linker_version_script = getattr(target_config, "linker_version_script", "")
        if linker_version_script:
            linkopts = linkopts + ["-Wl,--version-script,%s/%s" % (absolute_path, linker_version_script)]
        if compiler_extra_include:
            copts = copts + ["-include", "%s/glibc-hacks/%s" % (absolute_path, compiler_extra_include)]
            cxx_builtin_include_directories.append(absolute_path + "/glibc-hacks")

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_toolchain_config",
            target = zigtarget,
            target_suffix = getattr(target_config, "target_suffix", ""),
            tool_paths = absolute_tool_paths,
            cxx_builtin_include_directories = cxx_builtin_include_directories,
            copts = copts,
            linkopts = linkopts,
            target_cpu = target_config.bazel_target_cpu,
            target_system_name = "unknown",
            target_libc = "unknown",
            compiler = "clang",
            abi_version = "unknown",
            abi_libc_version = "unknown",
        )

        native.cc_toolchain(
            name = zigtarget + "_cc_toolchain",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_cc_toolchain_config" % zigtarget,
            all_files = ":zig",
            ar_files = ":zig",
            compiler_files = ":zig",
            linker_files = ":zig",
            dwp_files = ":empty",
            objcopy_files = ":empty",
            strip_files = ":empty",
            supports_param_files = 0,
        )

        # register two kinds of toolchain targets: Go and Zig conventions.
        # Go convention: amd64/arm64, linux/darwin
        native.toolchain(
            name = gotarget + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc_toolchain" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )

        # Zig convention: x86_64/aarch64, linux/macos
        native.toolchain(
            name = zigtarget + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc_toolchain" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
