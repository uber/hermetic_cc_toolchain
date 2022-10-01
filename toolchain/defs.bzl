load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("@bazel-zig-cc//toolchain/private:defs.bzl", "target_structs", "zig_tool_path")

# Directories that `zig c++` includes behind the scenes.
_DEFAULT_INCLUDE_DIRECTORIES = [
    "libcxx/include",
    "libcxxabi/include",
    "libunwind/include",
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

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. A real
# solution would be to allow the downstream project specify their own mirrors.
# This is explained in
# https://sr.ht/~motiejus/bazel-zig-cc/#alternative-download-urls and is
# awaiting my attention or your contribution.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"

# Author's mirror that doesn't purge the nightlies so aggressively. I will be
# cleaning those up manually only after the artifacts are not in use for many
# months in bazel-zig-cc. dl.jakstys.lt is a small x86_64 server with an NVMe
# drive sitting in my home closet on a 1GB/s symmetric residential connection,
# which, as of writing, has been quite reliable.
URL_FORMAT_JAKSTYS = "https://dl.jakstys.lt/zig/zig-{host_platform}-{version}.{_ext}"

_VERSION = "0.10.0-dev.4166+cae76d829"

_HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "0137b1e7225668ea41ef359ac50865b66b016d4048d0d1f082e50906a4ddcea4",
    "linux-x86_64": "071aaf393bca6142e9d002f995570b9a439bc09ebfbc4ec7c995619217e6b468",
    "macos-aarch64": "959564f213bab41a40ca0b0280f82e981b0c7afc0a46bf875f8a8c2e0bd776ae",
    "macos-x86_64": "563ddb8c58fde5efaa32d94756fd6095b5d229abbf3d1d7e6a9e54c3fcf69bb5",
    "windows-x86_64": "aa1c95e74b703a5946a168e404ce0f57e70db43e6c1c1ba89a65fab254df29c1",
}

_HOST_PLATFORM_EXT = {
    "linux-aarch64": "tar.xz",
    "linux-x86_64": "tar.xz",
    "macos-aarch64": "tar.xz",
    "macos-x86_64": "tar.xz",
    "windows-x86_64": "zip",
}

def toolchains(
        version = _VERSION,
        url_formats = [URL_FORMAT_NIGHTLY, URL_FORMAT_JAKSTYS],
        host_platform_sha256 = _HOST_PLATFORM_SHA256,
        host_platform_ext = _HOST_PLATFORM_EXT):
    """
        Download zig toolchain and declare bazel toolchains.
        The platforms are not registered automatically, that should be done by
        the user with register_toolchains() in the WORKSPACE file. See README
        for possible choices.
    """
    zig_repository(
        name = "zig_sdk",
        version = version,
        url_formats = url_formats,
        host_platform_sha256 = host_platform_sha256,
        host_platform_ext = host_platform_ext,
        host_platform_include_root = {
            "linux-aarch64": "lib/zig/",
            "linux-x86_64": "lib/",
            "macos-aarch64": "lib/",
            "macos-x86_64": "lib/zig/",
            "windows-x86_64": "lib/",
        },
    )

_ZIG_TOOLS = [
    "c++",
    "cc",
    "ar",
    "ld.lld",  # ELF
    "ld64.lld",  # Mach-O
    "lld-link",  # COFF
    "wasm-ld",  # WebAssembly
]

_ZIG_TOOL_WRAPPER_WINDOWS_CACHE_KNOWN = """@echo off
if exist "external\\zig_sdk\\lib\\*" goto :have_external_zig_sdk_lib
set ZIG_LIB_DIR=%~dp0\\..\\lib
goto :set_zig_lib_dir
:have_external_zig_sdk_lib
set ZIG_LIB_DIR=external\\zig_sdk\\lib
:set_zig_lib_dir
set ZIG_LOCAL_CACHE_DIR={cache_prefix}\\bazel-zig-cc
set ZIG_GLOBAL_CACHE_DIR=%ZIG_LOCAL_CACHE_DIR%
"{zig}" "{zig_tool}" %*
"""

_ZIG_TOOL_WRAPPER_WINDOWS_CACHE_GUESS = """@echo off
if exist "external\\zig_sdk\\lib\\*" goto :have_external_zig_sdk_lib
set ZIG_LIB_DIR=%~dp0\\..\\lib
goto :set_zig_lib_dir
:have_external_zig_sdk_lib
set ZIG_LIB_DIR=external\\zig_sdk\\lib
:set_zig_lib_dir
if exist "%TMP%\\*" goto :usertmp
set ZIG_LOCAL_CACHE_DIR=C:\\Temp\\bazel-zig-cc
goto zig
:usertmp
set ZIG_LOCAL_CACHE_DIR=%TMP%\\bazel-zig-cc
:zig
set ZIG_GLOBAL_CACHE_DIR=%ZIG_LOCAL_CACHE_DIR%
"{zig}" "{zig_tool}" %*
"""

_ZIG_TOOL_WRAPPER_CACHE_KNOWN = """#!/bin/sh
set -e
if [ -d external/zig_sdk/lib ]; then
    export ZIG_LIB_DIR=external/zig_sdk/lib
else
    export ZIG_LIB_DIR="$(dirname "$0")/../lib"
fi
export ZIG_LOCAL_CACHE_DIR="{cache_prefix}/bazel-zig-cc"
export ZIG_GLOBAL_CACHE_DIR="{cache_prefix}/bazel-zig-cc"
{common}
exec "{zig}" "{zig_tool}" "$@" $maybe_o2
"""

_ZIG_TOOL_WRAPPER_CACHE_GUESS = """#!/bin/sh
set -e
if [ -d external/zig_sdk/lib ]; then
    export ZIG_LIB_DIR=external/zig_sdk/lib
else
    export ZIG_LIB_DIR="$(dirname "$0")/../lib"
fi
if [ -n "$TMPDIR" ]; then
    _cache_prefix=$TMPDIR
elif [ -n "$HOME" ]; then
    if [ "$(uname)" = Darwin ]; then
        _cache_prefix="$HOME/Library/Caches"
    else
        _cache_prefix="$HOME/.cache"
    fi
else
    _cache_prefix=/tmp
fi
export ZIG_LOCAL_CACHE_DIR="$_cache_prefix/bazel-zig-cc"
export ZIG_GLOBAL_CACHE_DIR=$ZIG_LOCAL_CACHE_DIR
{common}
exec "{zig}" "{zig_tool}" "$@" $maybe_o2
"""

# The abomination below adds "-O2" to Go's link-prober command. Saves around
# 25s for the first compilation for a particular architecture. Can be deleted
# if/after https://go-review.googlesource.com/c/go/+/436884 is merged.
# Shell hackery taken from
# https://web.archive.org/web/20100129154217/http://www.seanius.net/blog/2009/03/saving-and-restoring-positional-params
_ZIG_TOOL_COMMON_UNIX = """
quote(){ echo "$1" | sed -e "s,','\\\\'',g"; }
for arg in "$@"; do saved="${saved:+$saved }'$(quote "$arg")'"; done
maybe_o2=
while [ "$#" -gt 6 ]; do shift; done
[ "$*" = "-Wl,--no-gc-sections -x c - -o /dev/null" ] && maybe_o2="-O2"
eval set -- "$saved"
"""

def _zig_tool_wrapper(zig_tool, zig, is_windows, cache_prefix):
    kwargs = dict(
        zig = str(zig).replace("/", "\\") + ".exe" if is_windows else zig,
        zig_tool = zig_tool,
        cache_prefix = cache_prefix,
        common = "" if is_windows else _ZIG_TOOL_COMMON_UNIX
    )

    if is_windows:
        if cache_prefix:
            return _ZIG_TOOL_WRAPPER_WINDOWS_CACHE_KNOWN.format(**kwargs)
        else:
            return _ZIG_TOOL_WRAPPER_WINDOWS_CACHE_GUESS.format(**kwargs)
    else:
        if cache_prefix:
            return _ZIG_TOOL_WRAPPER_CACHE_KNOWN.format(**kwargs)
        else:
            return _ZIG_TOOL_WRAPPER_CACHE_GUESS.format(**kwargs)

def _quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _zig_repository_impl(repository_ctx):
    arch = repository_ctx.os.arch
    if arch == "amd64":
        arch = "x86_64"

    os = repository_ctx.os.name.lower()
    if os.startswith("mac os"):
        os = "macos"

    if os.startswith("windows"):
        os = "windows"

    host_platform = "{}-{}".format(os, arch)

    zig_include_root = repository_ctx.attr.host_platform_include_root[host_platform]
    zig_sha256 = repository_ctx.attr.host_platform_sha256[host_platform]
    zig_ext = repository_ctx.attr.host_platform_ext[host_platform]
    format_vars = {
        "_ext": zig_ext,
        "version": repository_ctx.attr.version,
        "host_platform": host_platform,
    }

    # Fetch Label dependencies before doing download/extract.
    # The Bazel docs are not very clear about this behavior but see:
    # https://bazel.build/extending/repo#when_is_the_implementation_function_executed
    # and a related rules_go PR:
    # https://github.com/bazelbuild/bazel-gazelle/pull/1206
    for dest, src in {
        "platform/BUILD": "//toolchain/platform:BUILD",
        "toolchain/BUILD": "//toolchain/toolchain:BUILD",
        "libc/BUILD": "//toolchain/libc:BUILD",
        "libc_aware/platform/BUILD": "//toolchain/libc_aware/platform:BUILD",
        "libc_aware/toolchain/BUILD": "//toolchain/libc_aware/toolchain:BUILD",
    }.items():
        repository_ctx.symlink(Label(src), dest)

    for dest, src in {
        "BUILD": "//toolchain:BUILD.sdk.bazel",
        # "private/BUILD": "//toolchain/private:BUILD.sdk.bazel",
    }.items():
        repository_ctx.template(
            dest,
            Label(src),
            executable = False,
            substitutions = {
                "{zig_sdk_path}": _quote("external/zig_sdk"),
                "{os}": _quote(os),
                "{zig_include_root}": _quote(zig_include_root),
            },
        )

    urls = [uf.format(**format_vars) for uf in repository_ctx.attr.url_formats]
    repository_ctx.download_and_extract(
        auth = use_netrc(read_user_netrc(repository_ctx), urls, {}),
        url = urls,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = zig_sha256,
    )

    for zig_tool in _ZIG_TOOLS:
        zig_tool_wrapper = _zig_tool_wrapper(
            zig_tool,
            str(repository_ctx.path("zig")),
            os == "windows",
            repository_ctx.os.environ.get("BAZEL_ZIG_CC_CACHE_PREFIX", ""),
        )

        repository_ctx.file(
            zig_tool_path(os).format(zig_tool = zig_tool),
            zig_tool_wrapper,
        )

    repository_ctx.file(
        "glibc-hacks/fcntl.map",
        content = _fcntl_map,
    )
    repository_ctx.file(
        "glibc-hacks/glibchack-fcntl.h",
        content = _fcntl_h,
    )

zig_repository = repository_rule(
    attrs = {
        "version": attr.string(),
        "host_platform_sha256": attr.string_dict(),
        "url_formats": attr.string_list(allow_empty = False),
        "host_platform_include_root": attr.string_dict(),
        "host_platform_ext": attr.string_dict(),
    },
    environ = ["BAZEL_ZIG_CC_CACHE_PREFIX"],
    implementation = _zig_repository_impl,
)

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def declare_files(os, zig_include_root):
    filegroup(name = "all", srcs = native.glob(["**"]))
    filegroup(name = "empty")
    if os == "windows":
        native.exports_files(["zig.exe"], visibility = ["//visibility:public"])
        native.alias(name = "zig", actual = ":zig.exe")
    else:
        native.exports_files(["zig"], visibility = ["//visibility:public"])
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in target_structs():
        for d in _DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))
