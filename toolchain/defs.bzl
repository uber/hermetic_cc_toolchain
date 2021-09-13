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

# -Os, -O2 or -O3 must be set, because some dependencies use C's undefined
# behavior. See https://github.com/ziglang/zig/issues/4830
DEFAULT_COPTS = ["-O3"]

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
        copts = DEFAULT_COPTS,
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
        ],
        toplevel_include = ["glibc-hacks"] if fcntl_hack else [],
        compiler_extra_includes = ["glibc-hacks/glibchack-fcntl.h"] if fcntl_hack else [],
        linker_version_scripts = ["glibc-hacks/fcntl.map"] if fcntl_hack else [],
        linkopts = ["-lc++", "-lc++abi"],
        copts = DEFAULT_COPTS,
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
        copts = DEFAULT_COPTS + ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        tool_paths = {"ld": "ld.lld"},
    )

def register_toolchains(
        register = [],
        speed_first_safety_later = "auto"):
    """
        Download zig toolchain and register some.
        @param register registers the given toolchains to the system using
        native.register_toolchains(). See README for possible choices.
        @param speed_first_safety_later is a workaround for
        https://github.com/ziglang/zig/issues/9431
    """

    zig_repository(
        name = "zig_sdk",
        # Pre-release:
        version = "0.9.0-dev.953+211856693",
        url_format = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz",
        # Release:
        #version = "0.8.1",
        #url_format = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz",
        host_platform_sha256 = {
            "linux-x86_64": "acc6aff7efcb6e96fc489ade1cf7321eba21fdac8ac15ac12bfe4edb3587f3eb",
            "linux-aarch64": "ece15088f7588e2be3a2da698bc00a4327225e3ed94c52710a867a232880bdfd",
            "macos-x86_64": "87afe1c59490ab15294e0689a5265f614ba856c9efa568731383783d745cdce4",
            "macos-aarch64": "ad67c09fb89f417b2cb4691266d71f50c8a0e0eaaa423b08b074b15d307b788a",
        },
        host_platform_include_root = {
            "linux-aarch64": "lib/",
            "linux-x86_64": "lib/",
            "macos-aarch64": "lib/zig/",
            "macos-x86_64": "lib/zig/",
        },
        speed_first_safety_later = speed_first_safety_later,
    )

    toolchains = ["@zig_sdk//:%s_toolchain" % t for t in register]
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

# https://github.com/ziglang/zig/issues/9431
_flock=
if [[ -n "{do_flock}" ]]; then
  _flock=$(command -v flock || :)
  if [[ -z "$_flock" && -x /usr/local/bin/flock ]]; then
    _flock=/usr/local/bin/flock
  else
    >&2 echo "WARNING: flock not found, proceeding unsafely."
    >&2 echo "If build fails, retry it."
  fi
fi

if [[ -n "$_flock" ]]; then
  exec "$_flock" "{zig}" "{zig}" "{zig_tool}" "$@"
else
  exec "{zig}" "{zig_tool}" "$@"
fi
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
    res = repository_ctx.execute(["uname", "-m"])
    if res.return_code != 0:
        fail("failed to run uname -m")
    uname = res.stdout.strip()

    if repository_ctx.os.name.lower().startswith("mac os"):
        host_platform = "macos-{}".format(uname)
    else:
        host_platform = "linux-{}".format(uname)

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

    if repository_ctx.attr.speed_first_safety_later == "auto":
        do_flock = repository_ctx.os.name.lower().startswith("mac os")
    elif repository_ctx.attr.speed_first_safety_later == "yes":
        do_flock = False
    else:
        do_flock = True

    for zig_tool in _ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool = zig_tool),
            ZIG_TOOL_WRAPPER.format(
                zig = str(repository_ctx.path("zig")),
                zig_tool = zig_tool,
                do_flock = "1" if do_flock else "",
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
        },
    )

zig_repository = repository_rule(
    attrs = {
        "version": attr.string(),
        "host_platform_sha256": attr.string_dict(),
        "url_format": attr.string(),
        "host_platform_include_root": attr.string_dict(),
        "speed_first_safety_later": attr.string(
            values = ["yes", "no", "auto"],
            default = "auto",
            doc = "Workaround for github.com/ziglang/zig/issues/9431; " +
                  "dramatically decreases compilation time on multi-core " +
                  "hosts, but may fail compilation. Then re-run it. So far, " +
                  "the author has reproduced this only on OSX.",
        ),
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

def zig_build_macro(absolute_path, zig_include_root):
    filegroup(name = "empty")
    native.exports_files(["zig"], visibility = ["//visibility:public"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in _target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))
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
            name = zigtarget + "_toolchain_cc_config",
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
            name = zigtarget + "_toolchain_cc",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_toolchain_cc_config" % zigtarget,
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
            toolchain = ":%s_toolchain_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )

        # Zig convention: x86_64/aarch64, linux/macos
        native.toolchain(
            name = zigtarget + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_toolchain_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
