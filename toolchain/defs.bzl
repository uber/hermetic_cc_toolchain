load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("@bazel-zig-cc//toolchain/private:defs.bzl", "target_structs", "zig_tool_path")

# Directories that `zig c++` includes behind the scenes.
_DEFAULT_INCLUDE_DIRECTORIES = [
    "libcxx/include",
    "libcxxabi/include",
    "libunwind/include",
]

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

_VERSION = "0.11.0-dev.811+8ff9284c4"

_HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "b47358c3db3df92120e4659c86a653acbdb26fbeb11c97479b28634cbc68cd49",
    "linux-x86_64": "c24550551ac33b78d4f1534ae9dedde5a865c00d9de510e04c9e1e20e77ae18b",
    "macos-aarch64": "6fd768eab43dbc2bb3fae92b4c5c4ff538c90819b7c4fdf75bc4f6182d1745b3",
    "macos-x86_64": "5d227db2a9f89b46a940b229d93a53f5331923e676201f44322c1e2ceb62076f",
    "windows-x86_64": "b738ae6549d3a1fdefdd98d0e46fb638d1c5a8284e6c5320f72cbac97d202b37",
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
    )

_ZIG_TOOLS = [
    "c++",
    "ar",
]

_template_mapfile = """
%s {
    %s;
};
"""

_template_linker = """
#ifdef __ASSEMBLER__
.symver {from_function}, {to_function_abi}
#else
__asm__(".symver {from_function}, {to_function_abi}");
#endif
"""

def _glibc_hack(from_function, to_function_abi):
    # Cannot use .format(...) here, because starlark thinks
    # that the byte 3 (the opening brace on the first line)
    # is a nested { ... }, returning an error:
    # Error in format: Nested replacement fields are not supported
    to_function, to_abi = to_function_abi.split("@")
    mapfile = _template_mapfile % (to_abi, to_function)
    header = _template_linker.format(
        from_function = from_function,
        to_function_abi = to_function_abi,
    )
    return struct(
        mapfile = mapfile,
        header = header,
    )

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
            },
        )

    urls = [uf.format(**format_vars) for uf in repository_ctx.attr.url_formats]
    repository_ctx.download_and_extract(
        auth = use_netrc(read_user_netrc(repository_ctx), urls, {}),
        url = urls,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = zig_sha256,
    )

    cache_prefix = repository_ctx.os.environ.get("BAZEL_ZIG_CC_CACHE_PREFIX", "")
    if cache_prefix == "":
        if os == "windows":
            cache_prefix = "C:\\\\Temp\\\\bazel-zig-cc"
        else:
            cache_prefix = "/tmp/bazel-zig-cc"

    repository_ctx.template(
        "tools/launcher.zig",
        Label("//toolchain:launcher.zig"),
        executable = False,
        substitutions = {
            "{BAZEL_ZIG_CC_CACHE_PREFIX}": cache_prefix,
        },
    )

    ret = repository_ctx.execute(
        [
            paths.join("..", "zig"),
            "build-exe",
            "-OReleaseSafe",
            "launcher.zig",
        ] + (["-static"] if os == "linux" else []),
        working_directory = "tools",
        environment = {
            "ZIG_LOCAL_CACHE_DIR": cache_prefix,
            "ZIG_GLOBAL_CACHE_DIR": cache_prefix,
        },
    )
    if ret.return_code != 0:
        fail("compilation failed:\nreturn_code={}\nstderr={}\nstdout={}".format(
            ret.return_code,
            ret.stdout,
            ret.stderr,
        ))

    exe = ".exe" if os == "windows" else ""
    for target_config in target_structs():
        for zig_tool in _ZIG_TOOLS + target_config.tool_paths.values():
            tool_path = zig_tool_path(os).format(
                zig_tool = zig_tool,
                zigtarget = target_config.zigtarget,
            )
            repository_ctx.symlink("tools/launcher{}".format(exe), tool_path)

    fcntl_hack = _glibc_hack("fcntl64", "fcntl@GLIBC_2.2.5")
    repository_ctx.file("glibc-hacks/fcntl.map", content = fcntl_hack.mapfile)
    repository_ctx.file("glibc-hacks/fcntl.h", content = fcntl_hack.header)
    res_search_amd64 = _glibc_hack("res_search", "__res_search@GLIBC_2.2.5")
    repository_ctx.file("glibc-hacks/res_search-amd64.map", content = res_search_amd64.mapfile)
    repository_ctx.file("glibc-hacks/res_search-amd64.h", content = res_search_amd64.header)
    res_search_arm64 = _glibc_hack("res_search", "__res_search@GLIBC_2.17")
    repository_ctx.file("glibc-hacks/res_search-arm64.map", content = res_search_arm64.mapfile)
    repository_ctx.file("glibc-hacks/res_search-arm64.h", content = res_search_arm64.header)

zig_repository = repository_rule(
    attrs = {
        "version": attr.string(),
        "host_platform_sha256": attr.string_dict(),
        "url_formats": attr.string_list(allow_empty = False),
        "host_platform_ext": attr.string_dict(),
    },
    environ = ["BAZEL_ZIG_CC_CACHE_PREFIX"],
    implementation = _zig_repository_impl,
)

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def declare_files(os):
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
        all_includes = [native.glob(["lib/{}/**".format(i)]) for i in target_config.includes]
        all_includes.append(getattr(target_config, "compiler_extra_includes", []))

        cxx_tool_label = ":" + zig_tool_path(os).format(
            zig_tool = "c++",
            zigtarget = target_config.zigtarget,
        )

        filegroup(
            name = "{}_includes".format(target_config.zigtarget),
            srcs = _flatten(all_includes),
        )

        filegroup(
            name = "{}_compiler_files".format(target_config.zigtarget),
            srcs = [
                ":zig",
                ":{}_includes".format(target_config.zigtarget),
                cxx_tool_label,
            ],
        )

        filegroup(
            name = "{}_linker_files".format(target_config.zigtarget),
            srcs = [
                ":zig",
                ":{}_includes".format(target_config.zigtarget),
                cxx_tool_label,
            ] + native.glob([
                "lib/libc/{}/**".format(target_config.libc),
                "lib/libcxx/**",
                "lib/libcxxabi/**",
                "lib/libunwind/**",
                "lib/compiler_rt/**",
                "lib/std/**",
                "lib/*.zig",
                "lib/*.h",
            ]),
        )

        filegroup(
            name = "{}_ar_files".format(target_config.zigtarget),
            srcs = [
                ":zig",
                ":" + zig_tool_path(os).format(
                    zig_tool = "ar",
                    zigtarget = target_config.zigtarget,
                ),
            ],
        )

        filegroup(
            name = "{}_all_files".format(target_config.zigtarget),
            srcs = [
                ":{}_linker_files".format(target_config.zigtarget),
                ":{}_compiler_files".format(target_config.zigtarget),
                ":{}_ar_files".format(target_config.zigtarget),
            ],
        )

        for d in _DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = "lib/" + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name = d, srcs = native.glob([d + "/**"]))

def _flatten(iterable):
    result = []
    for element in iterable:
        result += element
    return result
