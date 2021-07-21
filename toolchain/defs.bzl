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

# https://github.com/ziglang/zig/blob/0cfa39304b18c6a04689bd789f5dc4d035ec43b0/src/main.zig#L2962-L2966
TARGET_CONFIGS_LISTOFLISTS = [[
    struct(
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
        register = True,
    ),
    struct(
        gotarget = "linux_{}_gnu".format(gocpu),
        zigtarget = "{}-linux-gnu".format(zigcpu),
        target_suffix = ".2.19",
        includes = [
            "libunwind/include",
            "libc/include/generic-glibc",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-gnu".format(zigcpu),
            "libc/include/{}-linux-any".format(zigcpu),
        ],
        linkopts = ["-lc++", "-lc++abi"],
        copts = [],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld.lld"},
        register = True,
    ),
    struct(
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
        register = False,
    ),
] for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64"))]

TARGET_CONFIGS = [val for sublist in TARGET_CONFIGS_LISTOFLISTS for val in sublist]

def toolchain_repositories():
    zig_repository(
        name = "zig_sdk",

        # Pre-release:
        version = "0.9.0-dev.347+628f490c5",
        url_format = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz",
        # Release:
        # version = "0.8.0",
        # url_format = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz",
        host_platform_sha256 = {
            "linux-x86_64": "163b2bdaf5464fcb94033c35737ec7c463bee4509e6970f19cfddb5bd90b2471",
            "macos-x86_64": "aa17c52c260b09328df8efd9b44f9197320a3d7b4d5c7025a715fc8ffe23ca35",
        },
        host_platform_include_root = {
            "macos-x86_64": "lib/zig/",
            "linux-x86_64": "lib/",
        },
    )

def register_all_toolchains():
    for target_config in TARGET_CONFIGS:
        if target_config.register:
            native.register_toolchains(
                "@zig_sdk//:%s_toolchain" % target_config.gotarget,
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
exec "{zig}" "{zig_tool}" "$@"
"""

ZIG_TOOLS = [
    "c++",
    "cc",
    "ar",
    # List of ld tools: https://github.com/ziglang/zig/blob/0cfa39304b18c6a04689bd789f5dc4d035ec43b0/src/main.zig#L2962-L2966
    # and also: https://github.com/ziglang/zig/issues/3257
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

    for zig_tool in ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool = zig_tool),
            ZIG_TOOL_WRAPPER.format(zig = str(repository_ctx.path("zig")), zig_tool = zig_tool),
        )

    repository_ctx.template(
        "BUILD.bazel",
        Label("//toolchain:BUILD.sdk.bazel"),
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
        "url_format": attr.string(),
        "host_platform_include_root": attr.string_dict(),
    },
    implementation = _zig_repository_impl,
)

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def zig_build_macro(absolute_path, zig_include_root):
    filegroup(name = "empty")
    native.exports_files(["zig"], visibility = ["//visibility:public"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in TARGET_CONFIGS:
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget
        native.platform(
            name = gotarget,
            constraint_values = target_config.constraint_values,
        )

        compiler_srcs = [":zig"]
        tool_srcs = {tool: [":zig"] for tool in ["gcc", "ld", "ar"]}

        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))
            compiler_srcs.append(lazy_filegroups[d])
            cxx_builtin_include_directories.append(absolute_path + "/" + d)

        absolute_tool_paths = {}
        for name, path in target_config.tool_paths.items() + DEFAULT_TOOL_PATHS:
            if path[0] == "/":
                absolute_tool_paths[name] = path
                continue
            tool_path = ZIG_TOOL_PATH.format(zig_tool = path)
            absolute_tool_paths[name] = "%s/%s" % (absolute_path, tool_path)
            tool_srcs[name].append(tool_path)

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_toolchain_config",
            target = zigtarget,
            target_suffix = getattr(target_config, "target_suffix", ""),
            tool_paths = absolute_tool_paths,
            cxx_builtin_include_directories = cxx_builtin_include_directories,
            copts = target_config.copts,
            linkopts = target_config.linkopts,
            target_system_name = "unknown",
            target_cpu = getattr(target_config, "bazel_target_cpu", None),
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

        native.toolchain(
            name = gotarget + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc_toolchain" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
