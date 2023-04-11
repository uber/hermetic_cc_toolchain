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

# Official Bazel's mirror with selected Zig SDK versions. Bazel community is
# generous enough to host the artifacts, which we use.
URL_FORMAT_BAZELMIRROR = "https://mirror.bazel.build/" + URL_FORMAT_NIGHTLY.lstrip("https://")

_VERSION = "0.11.0-dev.2545+311d50f9d"

_HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "9a4582c534802454775d2c3db33c472f55285b5203032d55fb13c5a41cc31833",
    "linux-x86_64": "b0895fe5d83dd361bd268580c9de5d5a3c42eaf966ea049bfae93eb537a88633",
    "macos-aarch64": "6f9aabd01d5200fe419e5fa54846e67f8342bf4cbebb71f735a729f4daaf4190",
    "macos-x86_64": "4bc1f1c28637b49b4ececdc819fc3d1a5d593560b8667183f26fe861b816279b",
    "windows-x86_64": "7673a442a59492235157d6e6549698fd183bd90d43db74bf93ac3611cb3aad46",
}

_HOST_PLATFORM_EXT = {
    "linux-aarch64": "tar.xz",
    "linux-x86_64": "tar.xz",
    "macos-aarch64": "tar.xz",
    "macos-x86_64": "tar.xz",
    "windows-x86_64": "zip",
}

_compile_failed = """
Compilation of launcher.zig failed:
command={compile_cmd}
return_code={return_code}
stderr={stderr}
stdout={stdout}

You most likely hit a rare but known race in Zig SDK. Congratulations?

We are working on fixing it with Zig Software Foundation. If you are curious,
feel free to follow along in https://github.com/ziglang/zig/issues/14815

There isn't much to do now but wait. Now apply the following workaround:
$ rm -fr {cache_prefix}
$ <... re-run your command ...>

... and proceed with your life.
"""

def toolchains(
        version = _VERSION,
        url_formats = [URL_FORMAT_BAZELMIRROR, URL_FORMAT_NIGHTLY],
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

    compile_env = {
        "ZIG_LOCAL_CACHE_DIR": cache_prefix,
        "ZIG_GLOBAL_CACHE_DIR": cache_prefix,
    }
    compile_cmd = [
        paths.join("..", "zig"),
        "build-exe",
        "-OReleaseSafe",
        "launcher.zig",
    ] + (["-static"] if os == "linux" else [])

    ret = repository_ctx.execute(
        compile_cmd,
        working_directory = "tools",
        environment = compile_env,
    )
    if ret.return_code != 0:
        full_cmd = [k + "=" + v for k, v in compile_env.items()] + compile_cmd
        fail(_compile_failed.format(
            compile_cmd = " ".join(full_cmd),
            return_code = ret.return_code,
            stdout = ret.stdout,
            stderr = ret.stderr,
            cache_prefix = cache_prefix,
        ))

    exe = ".exe" if os == "windows" else ""
    for target_config in target_structs():
        for zig_tool in _ZIG_TOOLS + target_config.tool_paths.values():
            tool_path = zig_tool_path(os).format(
                zig_tool = zig_tool,
                zigtarget = target_config.zigtarget,
            )
            repository_ctx.symlink("tools/launcher{}".format(exe), tool_path)

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
