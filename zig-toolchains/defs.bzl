load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(":zig_toolchain.bzl", "zig_cc_toolchain_config")

DEFAULT_TOOL_PATHS = {
    "ar": "llvm-ar", # TODO this should be "build-lib", see https://github.com/ziglang/zig/issues/7915
    "gcc": "c++", # https://github.com/bazelbuild/bazel/issues/4644

    # TODO See https://github.com/ziglang/zig/issues/7917 for zig issue to implement these other tools.
    "cpp": "/usr/bin/false",
    "gcov": "/usr/bin/false",
    "nm": "/usr/bin/false",
    "objdump": "/usr/bin/false",
    "strip": "/usr/bin/false",
}.items()

DEFAULT_INCLUDE_DIRECTORIES = [
    "include",
    # "libcxx/include",
    # "libcxxabi/include",
    # "libunwind/include",
]

# https://github.com/ziglang/zig/blob/0cfa39304b18c6a04689bd789f5dc4d035ec43b0/src/main.zig#L2962-L2966
TARGET_CONFIGS = [
    struct(
        target="x86_64-macos-gnu",
        includes=[
            "libcxx/include",
            "libcxxabi/include",
            "libunwind/include",
            "libc/include/any-macos-any",
            "libc/include/x86_64-macos-any",
            "libc/include/x86_64-macos-gnu",
        ],
        # linkopts=["-lc++", "-lc++abi"],
        linkopts=[],
        copts=[],
        bazel_target_cpu="darwin",
        constraint_values=["@platforms//os:macos", "@platforms//cpu:x86_64"],
        tool_paths={"ld": "ld64.lld"},
    ),
    struct(
        target="x86_64-linux-gnu.2.28",
        includes=[
            "libcxx/include",
            "libcxxabi/include",
            "libunwind/include",
            "libc/include/generic-glibc",
            "libc/include/any-linux-any",
            "libc/include/x86_64-linux-gnu",
            "libc/include/x86_64-linux-any",
        ],
        linkopts=["-lc++", "-lc++abi"],
        copts=[],
        bazel_target_cpu="k8",
        constraint_values=["@platforms//os:linux", "@platforms//cpu:x86_64"],
        tool_paths={"ld": "ld.lld"},
    ),
    # struct(
    #     target="x86_64-linux-musl",
    #     includes=[
    #         "libcxx/include",
    #         "libcxxabi/include",
    #         "libc/include/generic-musl",
    #         "libc/include/any-linux-any",
    #         "libc/include/x86_64-linux-musl",
    #         "libc/include/x86_64-linux-any",
    #     ],
    #     linkopts=[],
    #     # linkopts=["-lc++", "-lc++abi"],
    #     copts=["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
    #     constraint_values=["@platforms//os:linux", "@platforms//cpu:x86_64"],
    #     tool_paths={"ld": "ld.lld"},
    # ),
]

def toolchain_repositories():
    # We need llvm-ar for now, so get it.
    llvm_patch_cmds = [
        "mv bin/llvm-ar .",
        "rm -r include lib libexec share bin",
        "echo 'def noop(): pass' > noop.bzl",
    ]

    llvm_build_file_content = """
package(default_visibility = ["//visibility:public"])
exports_files(glob["**"])
"""
    http_archive(
        name = "com_github_ziglang_zig_llvm_tools_macos_x86_64",
        # sha256 = "",
        patch_cmds = llvm_patch_cmds,
        build_file_content = llvm_build_file_content,
        strip_prefix = "clang+llvm-11.0.0-x86_64-apple-darwin",
        urls = [
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/clang+llvm-11.0.0-x86_64-apple-darwin.tar.xz",
        ],
    )

    http_archive(
        name = "com_github_ziglang_zig_llvm_tools_linux_x86_64",
        sha256 = "829f5fb0ebda1d8716464394f97d5475d465ddc7bea2879c0601316b611ff6db",
        patch_cmds = llvm_patch_cmds,
        build_file_content = llvm_build_file_content,
        strip_prefix = "clang+llvm-11.0.0-x86_64-linux-gnu-ubuntu-20.04",
        urls = [
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/clang+llvm-11.0.0-x86_64-linux-gnu-ubuntu-20.04.tar.xz",
        ],
    )

    zig_repository(
        name = "com_github_ziglang_zig",

        version = "0.8.0-dev.2729+87dae0ce9",
        url_format = "https://ziglang.org/builds/zig-{host_platform}-{version}.tar.xz",
        host_platform_sha256 = {
            "linux-x86_64": "8f15f6cc88dd3afb0a6c0790aef8ee83fa7f7e3a8499154bc23c5b6d68ab74ed",
            "macos-x86_64": "2d410a4d5ababb61a1deccca724357fda4ed0277b722fc45ea10adf2ed215c5e",
        },

        # version = "0.7.1",
        # url_format = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz",
        # host_platform_sha256 = {
        #     "macos-x86_64": "845cb17562978af0cf67e3993f4e33330525eaf01ead9386df9105111e3bc519",
        #     "linux-x86_64": "18c7b9b200600f8bcde1cd8d7f1f578cbc3676241ce36d771937ce19a8159b8d",
        # },

        host_platform_include_root = {
            "macos-x86_64": "lib/zig/",
            "linux-x86_64": "lib/",
        }
    )

def register_all_toolchains():
    for target_config in TARGET_CONFIGS:
        native.register_toolchains(
            "@com_github_ziglang_zig//:%s_toolchain" % target_config.target,
        )

ZIG_TOOL_PATH = "tools/{zig_tool}"
ZIG_TOOL_WRAPPER = """#!/bin/bash
export HOME=$TMPDIR
exec "{zig}" "{zig_tool}" "$@"
"""

ZIG_TOOLS = [
    "c++",
    "cc",
    "build-lib", # https://github.com/ziglang/zig/issues/7915
    # List of ld tools: https://github.com/ziglang/zig/blob/0cfa39304b18c6a04689bd789f5dc4d035ec43b0/src/main.zig#L2962-L2966
    # and also: https://github.com/ziglang/zig/issues/3257
    "ld.lld", # ELF 
    "ld64.lld", # Mach-O
    "lld-link", # COFF
    "wasm-ld", # WebAssembly
]

TOOLS = ZIG_TOOLS + [
    "llvm-ar",
]

BUILD = """
load("@zig-cc-bazel-exceptions//zig-toolchains:defs.bzl", "zig_build_macro")
load("@{llvm_tools_repo}//:noop.bzl", "noop")
noop()
package(default_visibility = ["//visibility:public"])
zig_build_macro(absolute_path={absolute_path}, zig_include_root={zig_include_root})
"""

def _zig_repository_impl(repository_ctx):
    if repository_ctx.os.name.lower().startswith("mac os"):
        llvm_tools_repo = "com_github_ziglang_zig_llvm_tools_macos_x86_64"
        host_platform = "macos-x86_64"
    else:
        host_platform = "linux-x86_64"
        llvm_tools_repo = "com_github_ziglang_zig_llvm_tools_linux_x86_64"

    zig_include_root = repository_ctx.attr.host_platform_include_root[host_platform]
    zig_sha256 = repository_ctx.attr.host_platform_sha256[host_platform]
    format_vars = {
        "version" : repository_ctx.attr.version,
        "host_platform" : host_platform,
    }
    zig_url = repository_ctx.attr.url_format.format(**format_vars)

    repository_ctx.download_and_extract(
        url = zig_url,
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = zig_sha256,
    )

    # TODO Use llvm-ar for host platform until we have https://github.com/ziglang/zig/issues/7915
    llvm_tools_dir = str(repository_ctx.path("")) + "/../" + llvm_tools_repo
    repository_ctx.symlink(llvm_tools_dir + "/llvm-ar", ZIG_TOOL_PATH.format(zig_tool="llvm-ar"))

    for zig_tool in ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool=zig_tool),
            ZIG_TOOL_WRAPPER.format(zig=str(repository_ctx.path("zig")), zig_tool=zig_tool),
        )

    absolute_path = json.encode(str(repository_ctx.path("")))
    repository_ctx.file(
        "BUILD",
        BUILD.format(absolute_path=absolute_path, llvm_tools_repo=llvm_tools_repo, zig_include_root=json.encode(zig_include_root)),
    )

zig_repository = repository_rule(
    attrs = {
        "url": attr.string(),
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
    filegroup(name="empty")
    filegroup(name="zig_compiler", srcs=["zig"])
    filegroup(name="lib/std", srcs=native.glob(["lib/std/**"]))

    lazy_filegroups = {}

    for target_config in TARGET_CONFIGS:
        target = target_config.target
        native.platform(name = target, constraint_values = target_config.constraint_values)

        all_srcs = []
        ar_srcs = [":zig_compiler"]
        linker_srcs = [":zig_compiler"]
        compiler_srcs = [":zig_compiler"]
        tool_srcs = {"gcc": compiler_srcs, "ld": linker_srcs, "ar": ar_srcs}
        
        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
            if d not in lazy_filegroups:
                lazy_filegroups[d] = filegroup(name=d, srcs=native.glob([d + "/**"]))
            compiler_srcs.append(lazy_filegroups[d])
            cxx_builtin_include_directories.append(absolute_path + "/" + d)

        absolute_tool_paths = {}
        for name, path in target_config.tool_paths.items() + DEFAULT_TOOL_PATHS:
            if path[0] == "/":
                absolute_tool_paths[name] = path
                continue
            tool_path = ZIG_TOOL_PATH.format(zig_tool=path)
            absolute_tool_paths[name] = "%s/%s" % (absolute_path, tool_path)
            tool_srcs[name].append(tool_path)

        ar_files       = filegroup(name=target + "_ar_files",       srcs=ar_srcs)
        linker_files   = filegroup(name=target + "_linker_files",   srcs=linker_srcs)
        compiler_files = filegroup(name=target + "_compiler_files", srcs=compiler_srcs)
        all_files      = filegroup(name=target + "_all_files",      srcs=all_srcs + [ar_files, linker_files, compiler_files])

        zig_cc_toolchain_config(
            name = target + "_cc_toolchain_config",
            target = target,
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
            tags = ["manual"]
        )

        native.toolchain(
            name = target + "_toolchain",
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc_toolchain" % target,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
