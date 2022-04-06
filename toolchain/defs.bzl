load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
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

_fcntl_map = """
GLIBC_2.2.5 {
   fcntl;
};
"""
_fcntl_h = """
#ifdef __ASSEMBLER__
.symver fcntl64, fcntl@GLIBC_2.2.5
#else
__asm__(".symver fcntl64, fcntl@GLIBC_2.2.5");
#endif
"""

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

def _target_darwin(gocpu, zigcpu):
    min_os = "10"
    if zigcpu == "aarch64":
        min_os = "11"
    return struct(
        gotarget = "darwin_{}".format(gocpu),
        zigtarget = "{}-macos-gnu".format(zigcpu),
        includes = [
            "libunwind/include",
            # TODO: Define a toolchain for each minimum OS version
            "libc/include/{}-macos.{}-gnu".format(zigcpu, min_os),
            "libc/include/any-macos.{}-any".format(min_os),
            "libc/include/any-macos-any",
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

def _target_linux_gnu(gocpu, zigcpu, glibc_version = ""):
    glibc_suffix = "gnu"
    if glibc_version != "":
        glibc_suffix = "gnu.{}".format(glibc_version)

    # https://github.com/ziglang/zig/issues/5882#issuecomment-888250676
    # fcntl_hack is only required for glibc 2.27 or less. We assume that
    # glibc_version == "" (autodetect) is running a recent glibc version, thus
    # adding this hack only when glibc is explicitly 2.27 or lower.
    fcntl_hack = False
    if glibc_version == "":
        # zig doesn't reliably detect the glibc version, so
        # often falls back to 2.17; the hack should be included.
        # https://github.com/ziglang/zig/issues/6469
        fcntl_hack = True
    else:
        # hack is required for 2.27 or less.
        fcntl_hack = glibc_version < "2.28"

    return struct(
        gotarget = "linux_{}_{}".format(gocpu, glibc_suffix),
        zigtarget = "{}-linux-{}".format(zigcpu, glibc_suffix),
        includes = [
            "libunwind/include",
            "libc/include/generic-glibc",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-gnu".format(zigcpu),
            "libc/include/{}-linux-any".format(zigcpu),
        ] + (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []),
        toplevel_include = ["glibc-hacks"] if fcntl_hack else [],
        compiler_extra_includes = ["glibc-hacks/glibchack-fcntl.h"] if fcntl_hack else [],
        linker_version_scripts = ["glibc-hacks/fcntl.map"] if fcntl_hack else [],
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
        ] + (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []),
        linkopts = ["-s", "-w"],
        copts = ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld.lld"},
    )

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz"

# Caution: nightly releases are purged from ziglang.org after ~90 days. A real
# solution would be to allow the downstream project specify their own mirrors.
# This is explained in
# https://sr.ht/~motiejus/bazel-zig-cc/#alternative-download-urls and is
# awaiting my attention or your contribution.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz"

# Author's mirror that doesn't purge the nightlies so aggressively. I will be
# cleaning those up manually only after the artifacts are not in use for many
# months in bazel-zig-cc. dl.jakstys.lt is a small x86_64 server with an NVMe
# drive sitting in my home closet on a 1GB/s symmetric residential connection,
# which, as of writing, has been quite reliable.
URL_FORMAT_JAKSTYS = "https://dl.jakstys.lt/zig/zig-{host_platform}-{version}.tar.xz"

_VERSION = "0.10.0-dev.1393+291f5055f"

_HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "10c6618f57f6253c047098aee4093fe36e7fc4da7f0ed2451cca91e8b84575b8",
    "linux-x86_64": "de30008c98ba61791ab5caa78ec9fbe20c76f8e57c7a41e1cf5788d8f59b4c7e",
    "macos-aarch64": "72edc26973d697bba68f138701ebf9755548677ecedd853fd224baa836bef2f8",
    "macos-x86_64": "78220a4460a7c0f563d7365313fcd3ea028ed38166ebac55ba22f17ab6404851",
}

def register_toolchains(
        register = [],
        version = _VERSION,
        url_formats = [URL_FORMAT_JAKSTYS],
        host_platform_sha256 = _HOST_PLATFORM_SHA256):
    """
        Download zig toolchain and register some.
        @param register registers the given toolchains to the system using
        native.register_toolchains(). See README for possible choices.
    """
    zig_repository(
        name = "zig_sdk",
        version = version,
        url_formats = url_formats,
        host_platform_sha256 = host_platform_sha256,
        host_platform_include_root = {
            "linux-aarch64": "lib/",
            "linux-x86_64": "lib/",
            "macos-aarch64": "lib/zig/",
            "macos-x86_64": "lib/zig/",
        },
    )

    toolchains = ["@zig_sdk//:toolchain:%s" % t for t in register]
    native.register_toolchains(*toolchains)

ZIG_TOOL_PATH = "tools/{zig_tool}"
ZIG_TOOL_WRAPPER = """#!/bin/bash
set -e

if [[ -n "$TMPDIR" ]]; then
  _cache_prefix=$TMPDIR
else
  _cache_prefix="$HOME/.cache"
  if [[ "$(uname)" = Darwin ]]; then
    _cache_prefix="$HOME/Library/Caches"
  fi
fi
export ZIG_LOCAL_CACHE_DIR="$_cache_prefix/bazel-zig-cc"
export ZIG_GLOBAL_CACHE_DIR=$ZIG_LOCAL_CACHE_DIR

exec "{zig}" "{zig_tool}" "$@"
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
    arch = repository_ctx.os.arch
    if arch == "amd64":
        arch = "x86_64"

    os = repository_ctx.os.name.lower()
    if os.startswith("mac os"):
        os = "macos"

    host_platform = "{}-{}".format(os, arch)

    zig_include_root = repository_ctx.attr.host_platform_include_root[host_platform]
    zig_sha256 = repository_ctx.attr.host_platform_sha256[host_platform]
    format_vars = {
        "version": repository_ctx.attr.version,
        "host_platform": host_platform,
    }

    urls = [uf.format(**format_vars) for uf in repository_ctx.attr.url_formats]
    repository_ctx.download_and_extract(
        auth = use_netrc(read_user_netrc(repository_ctx), urls, {}),
        url = urls,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = zig_sha256,
    )

    for zig_tool in _ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool = zig_tool),
            ZIG_TOOL_WRAPPER.format(
                zig = str(repository_ctx.path("zig")),
                zig_tool = zig_tool,
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

    repository_ctx.symlink(
        Label("//toolchain/platform:BUILD"),
        "platform/BUILD",
    )
    repository_ctx.template(
        "BUILD",
        Label("//toolchain:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{zig_include_root}": shell.quote(zig_include_root),
        },
    )

    repository_ctx.template(
        "toolchain/BUILD",
        Label("//toolchain/toolchain:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{absolute_path}": shell.quote(str(repository_ctx.path(""))),
            "{zig_include_root}": shell.quote(zig_include_root),
        },
    )

zig_repository = repository_rule(
    attrs = {
        "version": attr.string(),
        "host_platform_sha256": attr.string_dict(),
        "url_formats": attr.string_list(allow_empty = False),
        "host_platform_include_root": attr.string_dict(),
    },
    implementation = _zig_repository_impl,
)

def _target_structs():
    ret = []
    for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64")):
        ret.append(_target_darwin(gocpu, zigcpu))
        ret.append(_target_linux_musl(gocpu, zigcpu))
        for glibc in [""] + _GLIBCS:
            ret.append(_target_linux_gnu(gocpu, zigcpu, glibc))
    return ret

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def declare_files(zig_include_root):
    filegroup(name = "empty")
    native.exports_files(["zig"], visibility = ["//visibility:public"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in _target_structs():
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))


def declare_toolchains(absolute_path, zig_include_root):
    for target_config in _target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            cxx_builtin_include_directories.append(absolute_path + "/" + d)
        for d in getattr(target_config, "toplevel_include", []):
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
        for s in getattr(target_config, "linker_version_scripts", []):
            linkopts = linkopts + ["-Wl,--version-script,%s/%s" % (absolute_path, s)]
        for incl in getattr(target_config, "compiler_extra_includes", []):
            copts = copts + ["-include", absolute_path + "/" + incl]

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_config",
            target = zigtarget,
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
            name = zigtarget + "_cc",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_cc_config" % zigtarget,
            all_files = "@zig_sdk//:zig",
            ar_files = "@zig_sdk//:zig",
            compiler_files = "@zig_sdk//:zig",
            linker_files = "@zig_sdk//:zig",
            dwp_files = "@zig_sdk//:empty",
            objcopy_files = "@zig_sdk//:empty",
            strip_files = "@zig_sdk//:empty",
            supports_param_files = 0,
        )

        # register two kinds of toolchain targets: Go and Zig conventions.
        # Go convention: amd64/arm64, linux/darwin
        native.toolchain(
            name = gotarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )

        # Zig convention: x86_64/aarch64, linux/macos
        native.toolchain(
            name = zigtarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
