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
        target = "{}-macos-gnu".format(cpu),
        includes = [
            "libunwind/include",
            "libc/include/any-macos-any",
            "libc/include/{}-macos-any".format(cpu),
            "libc/include/{}-macos-gnu".format(cpu),
        ],
        # linkopts=["-lc++", "-lc++abi"],
        linkopts = [],
        copts = [],
        bazel_target_cpu = "darwin",
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:{}".format(cpu),
        ],
        tool_paths = {"ld": "ld64.lld"},
    ),
    struct(
        target = "{}-linux-gnu".format(cpu),
        target_suffix = ".2.19",
        includes = [
            "libunwind/include",
            "libc/include/generic-glibc",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-gnu".format(cpu),
            "libc/include/{}-linux-any".format(cpu),
        ],
        linkopts = ["-lc++", "-lc++abi"],
        copts = [],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(cpu),
            ":libc_gnu",
        ],
        tool_paths = {"ld": "ld.lld"},
    ),
    struct(
        target = "{}-linux-musl".format(cpu),
        includes = [
            "libc/include/generic-musl",
            "libc/include/any-linux-any",
            "libc/include/{}-linux-musl".format(cpu),
            "libc/include/{}-linux-any".format(cpu),
        ],
        linkopts = ["-s", "-w"],
        copts = ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(cpu),
            ":libc_musl",
        ],
        tool_paths = {"ld": "ld.lld"},
    ),
] for cpu in ("x86_64", "aarch64")]

TARGET_CONFIGS = [val for sublist in TARGET_CONFIGS_LISTOFLISTS for val in sublist]

def toolchain_repositories():
    zig_repository(
        name = "zig_sdk",

        # Debug:
        version = "0.8.0-194-gb9e78593b",
        url_format = "https://jakstys.lt/mtpad/zig-{host_platform}-{version}.tar.xz",
        # Pre-release:
        #version = "0.9.0-dev.190+6f0cfdb82",
        #url_format = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz",
        # Release:
        # version = "0.8.0",
        # url_format = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz",
        host_platform_sha256 = {
            #"linux-x86_64": "a086a1749c0590af6b1089c1f9320f1637adf736c7b874017554a4e13ebac78a", # nightly
            "linux-x86_64": "869d437e4a2043029867fc23885eb1a58baa394b61907afe0dbac43e8264556a", # debug
            "macos-x86_64": "9b5e3fefa6ae0b1ab26821323df0641f818e72bffc343e194dc60829005d3055",
        },
        host_platform_include_root = {
            "macos-x86_64": "lib/zig/",
            "linux-x86_64": "lib/",
        },
    )

def register_all_toolchains():
    for target_config in TARGET_CONFIGS:
        native.register_toolchains(
            "@zig_sdk//:%s_toolchain" % target_config.target,
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

    absolute_path = json.encode(str(repository_ctx.path("")))
    repository_ctx.template(
        "BUILD.bazel",
        Label("//toolchain:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{absolute_path}": absolute_path,
            "{zig_include_root}": json.encode(zig_include_root),
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
    filegroup(name = "zig_compiler", srcs = ["zig"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    native.constraint_setting(name = "libc")

    native.constraint_value(
        name = "libc_musl",
        constraint_setting = ":libc",
    )

    native.constraint_value(
        name = "libc_gnu",
        constraint_setting = ":libc",
    )

    lazy_filegroups = {}

    for target_config in TARGET_CONFIGS:
        target = target_config.target
        native.platform(
            name = target,
            constraint_values = target_config.constraint_values,
        )

        all_srcs = []
        ar_srcs = [":zig_compiler"]
        linker_srcs = [":zig_compiler"]
        compiler_srcs = [":zig_compiler"]
        tool_srcs = {"gcc": compiler_srcs, "ld": linker_srcs, "ar": ar_srcs}

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

        ar_files = filegroup(name = target + "_ar_files", srcs = ar_srcs)
        linker_files = filegroup(name = target + "_linker_files", srcs = linker_srcs)
        compiler_files = filegroup(name = target + "_compiler_files", srcs = compiler_srcs)
        all_files = filegroup(name = target + "_all_files", srcs = all_srcs + [ar_files, linker_files, compiler_files])

        zig_cc_toolchain_config(
            name = target + "_cc_toolchain_config",
            target = target,
            target_suffix = getattr(target_config, "target_suffix", ""),
            tool_paths = absolute_tool_paths,
            cxx_builtin_include_directories = cxx_builtin_include_directories,
            copts = target_config.copts,
            linkopts = target_config.linkopts,
            target_system_name = "unknown",
            target_cpu = target_config.bazel_target_cpu,
            target_libc = "unknown",
            compiler = "clang",
            abi_version = "unknown",
            abi_libc_version = "unknown",
        )

        native.cc_toolchain(
            name = target + "_cc_toolchain",
            toolchain_identifier = target + "-toolchain",
            toolchain_config = ":%s_cc_toolchain_config" % target,
            all_files = all_files,
            ar_files = ar_files,
            compiler_files = compiler_files,
            linker_files = linker_files,
            dwp_files = ":empty",
            objcopy_files = ":empty",
            strip_files = ":empty",
            supports_param_files = 0,
        )

        native.cc_toolchain_suite(
            name = target + "_cc_toolchain_suite",
            toolchains = {
                target_config.bazel_target_cpu: ":%s_cc_toolchain" % target,
            },
            tags = ["manual"],
        )

        native.toolchain(
            name = target + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc_toolchain" % target,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
