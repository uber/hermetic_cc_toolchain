load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load(":zig_toolchain.bzl", "zig_cc_toolchain_config")

DEFAULT_TOOL_PATHS = {
    "ar": "llvm-ar", # TODO this should be "build-lib", see https://github.com/ziglang/zig/issues/7915
    "cpp": "c++",
    "gcc": "cc",

    # TODO See https://github.com/ziglang/zig/issues/7917 for zig issue to implement these other tools.
    "gcov": "/usr/bin/false",
    "nm": "/usr/bin/false",
    "objdump": "/usr/bin/false",
    "strip": "/usr/bin/false",
}.items()

DEFAULT_INCLUDE_DIRECTORIES = [
    "lib/zig/include",
    # "lib/zig/libcxx/include",
    # "lib/zig/libcxxabi/include",
    # "lib/zig/libunwind/include",
]

# https://github.com/ziglang/zig/blob/0cfa39304b18c6a04689bd789f5dc4d035ec43b0/src/main.zig#L2962-L2966
TARGET_CONFIGS = [
    struct(
        target="x86_64-linux-gnu.2.28",
        includes=[
            "lib/zig/libcxx/include",
            "lib/zig/libcxxabi/include",
            "lib/zig/libunwind/include",
            "lib/zig/libc/include/generic-glibc",
            "lib/zig/libc/include/any-linux-any",
            "lib/zig/libc/include/x86_64-linux-gnu",
            "lib/zig/libc/include/x86_64-linux-any",
        ],
        linkopts=["-lc++", "-lc++abi"],
        copts=[],
        constraint_values=["@platforms//os:linux", "@platforms//cpu:x86_64"],
        tool_paths={"ld": "ld.lld"},
    ),
    # struct(
    #     target="x86_64-linux-musl",
    #     includes=[
    #         "lib/zig/libcxx/include",
    #         "lib/zig/libcxxabi/include",
    #         "lib/zig/libc/include/generic-musl",
    #         "lib/zig/libc/include/any-linux-any",
    #         "lib/zig/libc/include/x86_64-linux-musl",
    #         "lib/zig/libc/include/x86_64-linux-any",
    #     ],
    #     linkopts=[],
    #     # linkopts=["-lc++", "-lc++abi"],
    #     copts=["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
    #     constraint_values=["@platforms//os:linux", "@platforms//cpu:x86_64"],
    #     tool_paths={"ld": "ld.lld"},
    # ),
]

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
zig_build_macro(absolute_path={absolute_path})
"""

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
        # sha256 = "",
        patch_cmds = llvm_patch_cmds,
        build_file_content = llvm_build_file_content,
        strip_prefix = "clang+llvm-11.0.0-x86_64-linux-gnu-ubuntu-20.04",
        urls = [
            "https://github.com/llvm/llvm-project/releases/download/llvmorg-11.0.0/clang+llvm-11.0.0-x86_64-linux-gnu-ubuntu-20.04.tar.xz",
        ],
    )

    zig_repository(
        name = "com_github_ziglang_zig",
        version = "0.7.1",
        sha256 = "845cb17562978af0cf67e3993f4e33330525eaf01ead9386df9105111e3bc519",
    )

def register_all_toolchains():
    for target_config in TARGET_CONFIGS:
        native.register_toolchains(
            "@com_github_ziglang_zig//:%s_toolchain" % target_config.target,
        )

def _zig_repository_impl(repository_ctx):
    if repository_ctx.os.name.lower().startswith("mac os"):
        llvm_tools_repo = "com_github_ziglang_zig_llvm_tools_macos_x86_64"
        host_platform = "macos-x86_64"
    else:
        host_platform = "linux-x86_64"
        llvm_tools_repo = "com_github_ziglang_zig_llvm_tools_linux_x86_64"

    format_vars = {
        "version" : repository_ctx.attr.version,
        "host_platform" : host_platform,
    }

    repository_ctx.download_and_extract(
        url = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.tar.xz".format(**format_vars),
        stripPrefix = "zig-{host_platform}-{version}/".format(**format_vars),
        sha256 = repository_ctx.attr.sha256,
    )

    # TODO Use llvm-ar for host platform until we have https://github.com/ziglang/zig/issues/7915
    llvm_tools_dir = str(repository_ctx.path("")) + "/../" + llvm_tools_repo + "/llvm-ar"
    repository_ctx.symlink(llvm_tools_dir, ZIG_TOOL_PATH.format(zig_tool="llvm-ar"))

    for zig_tool in ZIG_TOOLS:
        repository_ctx.file(
            ZIG_TOOL_PATH.format(zig_tool=zig_tool),
            ZIG_TOOL_WRAPPER.format(zig=str(repository_ctx.path("zig")), zig_tool=zig_tool),
        )

    absolute_path = json.encode(str(repository_ctx.path("")))
    repository_ctx.file(
        "BUILD",
        BUILD.format(absolute_path=absolute_path, llvm_tools_repo=llvm_tools_repo),
    )

zig_repository = repository_rule(
    attrs = {
        "url": attr.string(),
        "version": attr.string(),
        "sha256": attr.string(),
    },
    implementation = _zig_repository_impl,
)

def filegroup(name, **kwargs):
    native.filegroup(name = name, **kwargs)
    return ":" + name

def zig_build_macro(absolute_path):
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
        tool_srcs = {"gcc": compiler_srcs, "cpp": compiler_srcs, "ld": linker_srcs, "ar": ar_srcs}
        
        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
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
            # TODO don't hardcode this to k8
            target_cpu = "k8",
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
                # TODO don't hardcode this to k8
                "k8": ":%s_cc_toolchain" % target,
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
