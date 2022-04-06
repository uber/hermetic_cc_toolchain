load("@bazel-zig-cc//toolchain:zig_toolchain.bzl", "zig_cc_toolchain_config")
load("@bazel-zig-cc//toolchain/private:defs.bzl", "DEFAULT_INCLUDE_DIRECTORIES", "ZIG_TOOL_PATH", "target_structs")

DEFAULT_TOOL_PATHS = {
    "ar": "ar",
    "gcc": "c++",  # https://github.com/bazelbuild/bazel/issues/4644
    "cpp": "/usr/bin/false",
    "gcov": "/usr/bin/false",
    "nm": "/usr/bin/false",
    "objdump": "/usr/bin/false",
    "strip": "/usr/bin/false",
}.items()

def declare_toolchains(absolute_path, zig_include_root):
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []
        for d in DEFAULT_INCLUDE_DIRECTORIES + target_config.includes:
            d = zig_include_root + d
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
            name = zigtarget + "_cc_config",
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
            name = zigtarget + "_cc",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_cc_config" % zigtarget,
            all_files = "@zig_sdk//:zig",
            ar_files = "@zig_sdk//:zig",
            compiler_files = "@zig_sdk//:zig",
            linker_files = "@zig_sdk//:zig",
            dwp_files = "@zig_sdk//:empty",
            objcopy_files = "@zig_sdk//:empty",
            strip_files = "@zig_sdk//:empty",
            supports_param_files = 0,
        )

        # register two kinds of toolchain targets: Go and Zig conventions.
        # Go convention: amd64/arm64, linux/darwin
        native.toolchain(
            name = gotarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )

        # Zig convention: x86_64/aarch64, linux/macos
        native.toolchain(
            name = zigtarget,
            exec_compatible_with = None,
            target_compatible_with = target_config.constraint_values,
            toolchain = ":%s_cc" % zigtarget,
            toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
        )
