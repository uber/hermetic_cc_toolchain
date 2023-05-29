load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "target_structs", "zig_tool_path")

_BUILTIN_TOOLS = ["ar", "ld.lld", "lld-link"]

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
URL_FORMAT_BAZELMIRROR = "https://mirror.bazel.build/ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"

_VERSION = "0.11.0-dev.3312+ab37ab33c"

_HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "c155d5244c232e7878effb5c6c9f84fdcb443cad343ad4ce5936bcaad0a1a959",
    "linux-x86_64": "fdc3adf212d3ed790ea8b44293256324a90ebb5ba9647c01f4d435e2cf49dbd7",
    "macos-aarch64": "19f9115410a6dfb004c65d63ffecf947efc595d08977906f73a90d7b2de0b3dc",
    "macos-x86_64": "781e4f61f2de016b66ba17aaed5a56643bf5c9288d946de2c47ce5bdb829721b",
    "windows-x86_64": "b5301fc0bf7c67dfefe5c1e8f2ee3aad990a5d1a92b0322f8344ed608168934f",
}

_HOST_PLATFORM_EXT = {
    "linux-aarch64": "tar.xz",
    "linux-x86_64": "tar.xz",
    "macos-aarch64": "tar.xz",
    "macos-x86_64": "tar.xz",
    "windows-x86_64": "zip",
}

_MCPU = {
    "linux-aarch64": "baseline",
    "linux-x86_64": "baseline",
    "macos-aarch64": "apple_a14",
    "macos-x86_64": "baseline",
    "windows-x86_64": "baseline",
}

_compile_failed = """
Compilation of zig-wrapper.zig failed:
command={compile_cmd}
return_code={return_code}
stderr={stderr}
stdout={stdout}

You stumbled into a problem with Zig SDK that bazel-zig-cc was not able to fix.
Please file a new issue to github.com/uber/hermetic_cc_toolchain with:
- Full output of this Bazel run, including the Bazel command.
- Version of the Zig SDK if you have a non-default.
- Version of hermetic_cc_toolchain

Note: this *may* have been https://github.com/ziglang/zig/issues/14978, for
which hermetic_cc_toolchain has a workaround and you may have been "struck by
lightning" three times in a row.
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
            cache_prefix = "/tmp/zig-cache"

    repository_ctx.template(
        "tools/zig-wrapper.zig",
        Label("//toolchain:zig-wrapper.zig"),
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
        "-mcpu={}".format(_MCPU[host_platform]),
        "-OReleaseSafe",
        "zig-wrapper.zig",
    ] + (["-static"] if os == "linux" else [])

    # The elaborate code below is a workaround for ziglang/zig#14978: a race in
    # Windows where zig may error with `error: AccessDenied`.
    zig_wrapper_success = True
    zig_wrapper_err_msg = ""
    for _ in range(3):
        if not zig_wrapper_success:
            print("Launcher compilation failed. Retrying build")

        ret = repository_ctx.execute(
            compile_cmd,
            working_directory = "tools",
            environment = compile_env,
        )

        if ret.return_code == 0:
            zig_wrapper_success = True
            break

        zig_wrapper_success = False
        full_cmd = [k + "=" + v for k, v in compile_env.items()] + compile_cmd
        zig_wrapper_err_msg = _compile_failed.format(
            compile_cmd = " ".join(full_cmd),
            return_code = ret.return_code,
            stdout = ret.stdout,
            stderr = ret.stderr,
            cache_prefix = cache_prefix,
        )

    if not zig_wrapper_success:
        fail(zig_wrapper_err_msg)

    exe = ".exe" if os == "windows" else ""
    for t in _BUILTIN_TOOLS:
        repository_ctx.symlink("tools/zig-wrapper{}".format(exe), "tools/{}{}".format(t, exe))

    for target_config in target_structs():
        tool_path = zig_tool_path(os).format(
            zig_tool = "c++",
            zigtarget = target_config.zigtarget,
        )
        repository_ctx.symlink("tools/zig-wrapper{}".format(exe), tool_path)

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
    exe = ".exe" if os == "windows" else ""

    native.exports_files(["zig{}".format(exe)], visibility = ["//visibility:public"])
    if os == "windows":
        native.alias(name = "zig", actual = ":zig.exe")
        for t in _BUILTIN_TOOLS + ["zig-wrapper"]:
            native.alias(name = "tools/{}".format(t), actual = ":tools/{}.exe".format(t))

    filegroup(name = "all", srcs = native.glob(["**"]))
    filegroup(name = "lib/std", srcs = native.glob(["lib/std/**"]))
    filegroup(name = "empty")
    lazy_filegroups = {}

    for target_config in target_structs():
        all_includes = [native.glob(["lib/{}/**".format(i)]) for i in target_config.includes]

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
            srcs = [":zig", ":tools/ar{}".format(exe)],
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
