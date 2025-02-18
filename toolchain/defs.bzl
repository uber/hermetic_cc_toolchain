load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "read_user_netrc", "use_netrc")
load("@hermetic_cc_toolchain//toolchain/private:defs.bzl", "target_structs", "transform_os_name", "zig_tool_path")
load("@hermetic_cc_toolchain//toolchain/private:repositories.bzl", "zig_sdk_repository")
load(
    "@hermetic_cc_toolchain//toolchain/private:zig_sdk.bzl",
    "HOST_PLATFORM_SHA256",
    "URL_FORMAT_NIGHTLY",
    "URL_FORMAT_RELEASE",
    "VERSION",
)

_BUILTIN_TOOLS = ["ar", "ld.lld", "lld-link"]

# Directories that `zig c++` includes behind the scenes.
_DEFAULT_INCLUDE_DIRECTORIES = [
    "libcxx/include",
    "libcxxabi/include",
    "libunwind/include",
]

_HOST_PLATFORM_EXT = {
    "linux-aarch64": "tar.xz",
    "linux-x86_64": "tar.xz",
    "macos-aarch64": "tar.xz",
    "macos-x86_64": "tar.xz",
    "windows-x86_64": "zip",
    "windows-aarch64": "zip",
}

# map bazel's host_platform to zig's -target= and -mcpu=
_TARGET_MCPU = {
    "linux-aarch64": ("aarch64-linux-musl", "baseline"),
    "linux-x86_64": ("x86_64-linux-musl", "baseline"),
    "macos-aarch64": ("aarch64-macos-none", "apple_a14"),
    "macos-x86_64": ("x86_64-macos-none", "baseline"),
    "windows-x86_64": ("x86_64-windows-gnu", "baseline"),
    "windows-aarch64": ("aarch64-windows-gnu", "baseline"),
}

_compile_failed = """
Compilation of zig-wrapper.zig failed:
command={compile_cmd}
return_code={return_code}
stderr={stderr}
stdout={stdout}

You stumbled into a problem with Zig SDK that hermetic_cc_toolchain was not
able to fix. This is most likely a long-standing problem mostly (only?)
observed in OSX. Please please add a comment to
https://github.com/ziglang/zig/issues/18763 with:
- Output of `bazel run @zig_sdk//:zig version`
- Full output of this Bazel run, including the Bazel command.
- Full OS version and hardware revision (e.g. aarch64 or x86_64?).

Zig and hermetic_cc_toolchain maintainers aren't able to reproduce it, but you
are. Thus we need a bit of your collaboration to get to the bottom of it.

After commenting on the issue, `rm -fr {cache_prefix}` and re-run your command.
"""

def toolchains(
        version = VERSION,
        url_formats = [],
        host_platform_sha256 = HOST_PLATFORM_SHA256,
        host_platform_ext = _HOST_PLATFORM_EXT,
        exec_platforms = {}):
    """
        Download zig toolchain and declare bazel toolchains.
        The platforms are not registered automatically, that should be done by
        the user with register_toolchains() in the WORKSPACE file. See README
        for possible choices.
    """

    if not url_formats:
        if "dev" in version:
            original_format = URL_FORMAT_NIGHTLY
        else:
            original_format = URL_FORMAT_RELEASE

        mirror_format = original_format.replace("https://ziglang.org/", "https://mirror.bazel.build/ziglang.org/")
        url_formats = [mirror_format, original_format]

    indirect_repos = []

    host_only = not bool(exec_platforms)

    zig_sdk_repository(
        name = "zig_sdk",
        exec_platforms = exec_platforms,
        host_only = host_only,
    )

    # If `exec_platforms` dict is not specified by user in WORKSPACE,
    # create configs just for the HOST.
    if host_only:
        zig_repository(
            name = "zig_config",
            version = version,
            url_formats = url_formats,
            host_platform_sha256 = host_platform_sha256,
            host_platform_ext = host_platform_ext,
        )
        indirect_repos.append("zig_config")

    else:
        for os, archs in exec_platforms.items():
            for arch in archs:
                zig_repository(
                    name = "zig_config-{}-{}".format(os, arch),
                    version = version,
                    url_formats = url_formats,
                    host_platform_sha256 = host_platform_sha256,
                    host_platform_ext = host_platform_ext,
                    exec_os = os,
                    exec_arch = arch,
                )
                indirect_repos.append("zig_config-{}-{}".format(os, arch))

    return struct(
        direct = ["zig_sdk"],
        indirect = indirect_repos,
    )

def _quote(s):
    return "'" + s.replace("'", "'\\''") + "'"

def _zig_repository_impl(repository_ctx):
    exec_os = repository_ctx.attr.exec_os
    exec_arch = repository_ctx.attr.exec_arch
    host_os = repository_ctx.os.name
    host_arch = repository_ctx.os.arch

    if exec_os == "HOST":
        exec_os = host_os
    if exec_arch == "HOST":
        exec_arch = host_arch

    # transform {host,exec}_arch to conform _HOST_PLATFORM_EXT keys
    if exec_arch == "amd64":
        exec_arch = "x86_64"
    if host_arch == "amd64":
        host_arch = "x86_64"
    if host_arch == "arm64":
        host_arch = "aarch64"
    if exec_arch == "arm64":
        exec_arch = "aarch64"

    exec_os = transform_os_name(exec_os)
    host_os = transform_os_name(host_os)

    host_platform = "{}-{}".format(host_os, host_arch)
    exec_platform = "{}-{}".format(exec_os, exec_arch)

    zig_sha256 = repository_ctx.attr.host_platform_sha256[host_platform]
    zig_ext = repository_ctx.attr.host_platform_ext[host_platform]
    format_vars = {
        "_ext": zig_ext,
        "version": repository_ctx.attr.version,
        "host_platform": host_platform,
    }
    format_vars_exec = {
        "_ext": repository_ctx.attr.host_platform_ext[exec_platform],
        "version": repository_ctx.attr.version,
        "host_platform": exec_platform,
    }

    for dest, src in {
        "BUILD": "//toolchain:BUILD.sdk.bazel",
    }.items():
        repository_ctx.template(
            dest,
            Label(src),
            executable = False,
            substitutions = {
                "{zig_sdk_path}": _quote("external/zig_sdk"),
                "{os}": _quote(exec_os),
                "{exec_os}": exec_os,
                "{exec_cpu}": exec_arch,
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
        if host_os == "windows":
            cache_prefix = "C:\\\\Temp\\\\zig-cache"
        elif host_os == "macos":
            cache_prefix = "/var/tmp/zig-cache"
        elif host_os == "linux":
            cache_prefix = "/tmp/zig-cache"
        else:
            fail("unknown os: {}".format(host_os))

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
        "-target",
        _TARGET_MCPU[exec_platform][0],
        "-mcpu={}".format(_TARGET_MCPU[exec_platform][1]),
        "-fstrip",
        "-OReleaseSafe",
        "zig-wrapper.zig",
    ]

    # The elaborate code below is a workaround for ziglang/zig#18763:
    # Sometimes, when Zig's cache is empty, compiling the launcher may fail
    # with `error: FileNotFound`. We need users to report the full error
    # message.
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

    exe = ".exe" if exec_os == "windows" else ""
    for t in _BUILTIN_TOOLS:
        repository_ctx.symlink("tools/zig-wrapper{}".format(exe), "tools/{}{}".format(t, exe))

    urls = [uf.format(**format_vars_exec) for uf in repository_ctx.attr.url_formats]

    repository_ctx.download_and_extract(
        auth = use_netrc(read_user_netrc(repository_ctx), urls, {}),
        url = urls,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars_exec),
        sha256 = repository_ctx.attr.host_platform_sha256[exec_platform],
    )

    for target_config in target_structs():
        tool_path = zig_tool_path(exec_os).format(
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
        "exec_os": attr.string(default = "HOST"),
        "exec_arch": attr.string(default = "HOST"),
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
                "lib/tsan/**",
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
