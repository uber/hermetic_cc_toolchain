load(":defs.bzl", "target_structs", "zig_tool_path")
load("@hermetic_cc_toolchain//toolchain:zig_toolchain.bzl", "zig_cc_toolchain_config")

DEFAULT_TOOL_PATHS = {
    "ar": "ar",
    "gcc": "c++",  # https://github.com/bazelbuild/bazel/issues/4644
    "cpp": "/usr/bin/false",
    "gcov": "/usr/bin/false",
    "nm": "/usr/bin/false",
    "objdump": "/usr/bin/false",
    "strip": "/usr/bin/false",
}.items()

def declare_cc_toolchains(os, zig_sdk_path):
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []
        absolute_tool_paths = {}
        for name, path in target_config.tool_paths.items() + DEFAULT_TOOL_PATHS:
            if path[0] == "/":
                absolute_tool_paths[name] = path
                continue
            tool_path = zig_tool_path(os).format(
                zig_tool = path,
                zigtarget = zigtarget,
            )
            absolute_tool_paths[name] = tool_path

        dynamic_library_linkopts = target_config.dynamic_library_linkopts
        copts = target_config.copts
        linkopts = []

        # We can't pass a list of structs to a rule, so we use json encoding.
        artifact_name_patterns = getattr(target_config, "artifact_name_patterns", [])
        artifact_name_pattern_strings = [json.encode(p) for p in artifact_name_patterns]

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_config",
            target = zigtarget,
            tool_paths = absolute_tool_paths,
            cxx_builtin_include_directories = cxx_builtin_include_directories,
            copts = copts,
            linkopts = linkopts,
            dynamic_library_linkopts = dynamic_library_linkopts,
            target_cpu = target_config.bazel_target_cpu,
            target_system_name = "unknown",
            target_libc = "unknown",
            compiler = "clang",
            abi_version = "unknown",
            abi_libc_version = "unknown",
            artifact_name_patterns = artifact_name_pattern_strings,
            visibility = ["//visibility:private"],
        )

        native.cc_toolchain(
            name = zigtarget + "_cc",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_cc_config" % zigtarget,
            all_files = "@zig_sdk//:%s_all_files" % zigtarget,
            ar_files = "@zig_sdk//:%s_ar_files" % zigtarget,
            compiler_files = "@zig_sdk//:%s_compiler_files" % zigtarget,
            linker_files = "@zig_sdk//:%s_linker_files" % zigtarget,
            dwp_files = "@zig_sdk//:empty",
            objcopy_files = "@zig_sdk//:empty",
            strip_files = "@zig_sdk//:empty",
            supports_param_files = 0,
            visibility = ["//visibility:private"],
        )
