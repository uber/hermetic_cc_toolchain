load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "target_structs", "zig_tool_path")

# Directories that `zig c++` includes behind the scenes.
_DEFAULT_INCLUDE_DIRECTORIES = [
    "libcxx/include",
    "libcxxabi/include",
    "libunwind/include",
]

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
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

You stumbled into a problem with Zig SDK that bazel-zig-cc was not able to fix.
Please file a new issue to github.com/uber/bazel-zig-cc with:
- Full output of this Bazel run, including the Bazel command.
- Version of the Zig SDK if you have a non-default.
- Version of bazel-zig-cc.

Note: this *may* have been https://github.com/ziglang/zig/issues/14815, for
which bazel-zig-cc has a workaround and you may have been "struck by lightning"
three times in a row.
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

    cache_prefix = repository_ctx.os.environ.get("HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX", "")
    if cache_prefix == "":
        if os == "windows":
            cache_prefix = "C:\\\\Temp\\\\hermetic_cc_toolchain"
        else:
            cache_prefix = "/tmp/hermetic_cc_toolchain"

    repository_ctx.template(
        "tools/launcher.zig",
        Label("//toolchain:launcher.zig"),
        executable = False,
        substitutions = {
            "{HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX}": cache_prefix,
        },
    )

    compile_env = {
        "ZIG_LOCAL_CACHE_DIR": cache_prefix,
        "ZIG_GLOBAL_CACHE_DIR": cache_prefix,
    }
    compile_cmd = [
        _paths_join("..", "zig"),
        "build-exe",
        "-OReleaseSafe",
        "launcher.zig",
    ] + (["-static"] if os == "linux" else [])

    # The elaborate code below is a workaround for ziglang/zig#14815:
    # Sometimes, when Zig's cache is empty, compiling the launcher may fail
    # with `error: FileNotFound`. The remedy is to clear the cache and try
    # again. Until this change, we have been asking users to clear the Zig
    # cache themselves and re-run the Bazel command.
    #
    # We can do better than that: if we detect the launcher failed, we can
    # purge the zig cache and retry the compilation. It will be retried for up
    # to two times.
    launcher_success = True
    launcher_err_msg = ""
    for _ in range(3):
        # Do not remove the cache_prefix itself, because it is not controlled
        # by this script. Instead, clear the cache subdirs that we know Zig
        # populates.
        zig_cache_dirs = ["h", "o", "tmp", "z"]
        if not launcher_success:
            print("Launcher compilation failed. Clearing %s/{%s} and retrying" %
                  (cache_prefix, ",".join(zig_cache_dirs)))
            for d in zig_cache_dirs:
                repository_ctx.delete(_paths_join(cache_prefix, d))

        ret = repository_ctx.execute(
            compile_cmd,
            working_directory = "tools",
            environment = compile_env,
        )

        if ret.return_code == 0:
            launcher_success = True
            break

        launcher_success = False
        full_cmd = [k + "=" + v for k, v in compile_env.items()] + compile_cmd
        launcher_err_msg = _compile_failed.format(
            compile_cmd = " ".join(full_cmd),
            return_code = ret.return_code,
            stdout = ret.stdout,
            stderr = ret.stderr,
            cache_prefix = cache_prefix,
        )

    if not launcher_success:
        fail(launcher_err_msg)

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
    environ = ["HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX"],
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

## Copied from https://github.com/bazelbuild/bazel-skylib/blob/1.4.1/lib/paths.bzl#L59-L98
def _paths_is_absolute(path):
    return path.startswith("/") or (len(path) > 2 and path[1] == ":")

def _paths_join(path, *others):
    result = path
    for p in others:
        if _paths_is_absolute(p):
            result = p
        elif not result or result.endswith("/"):
            result += p
        else:
            result += "/" + p
    return result
