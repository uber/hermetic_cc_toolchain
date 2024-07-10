load(":defs.bzl", "target_structs", "zig_tool_path")
load("@hermetic_cc_toolchain//toolchain:zig_toolchain.bzl", "zig_cc_toolchain_config")

def declare_cc_toolchains(os, zig_sdk_path, macos_sdk_versions):
    exe = ".exe" if os == "windows" else ""

    for target_config in target_structs(macos_sdk_versions):
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []

        tool_paths = {}

        for tool in ["cpp", "gcov", "nm", "objdump", "strip"]:
            tool_paths[tool] = "/usr/bin/false"

        # https://github.com/bazelbuild/bazel/issues/4644
        tool_paths["gcc"] = zig_tool_path(os).format(
            zig_tool = "c++",
            zigtarget = zigtarget,
        )
        tool_paths["ar"] = "tools/ar{}".format(exe)

        if target_config.ld_zig_subcmd:
            tool_paths["ld"] = "tools/{}{}".format(target_config.ld_zig_subcmd, exe)
        else:
            tool_paths["ld"] = "/usr/bin/false"

        dynamic_library_linkopts = target_config.dynamic_library_linkopts
        supports_dynamic_linker = target_config.supports_dynamic_linker
        copts = target_config.copts
        linkopts = target_config.linkopts

        # We can't pass a list of structs to a rule, so we use json encoding.
        artifact_name_patterns = getattr(target_config, "artifact_name_patterns", [])
        artifact_name_pattern_strings = [json.encode(p) for p in artifact_name_patterns]

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_config",
            target = zigtarget,
            tool_paths = tool_paths,
            cxx_builtin_include_directories = getattr(
                target_config,
                "cxx_builtin_include_directories",
                [],
            ),
            copts = copts,
            linkopts = linkopts,
            dynamic_library_linkopts = dynamic_library_linkopts,
            supports_dynamic_linker = supports_dynamic_linker,
            target_cpu = target_config.bazel_target_cpu,
            target_system_name = "unknown",
            target_libc = "unknown",
            compiler = "clang",
            abi_version = "unknown",
            abi_libc_version = "unknown",
            artifact_name_patterns = artifact_name_pattern_strings,
            visibility = ["//visibility:private"],
            sysroot = "@macos_sdk_14.4//:sysroot",
            linkoptsF = "@macos_sdk_14.4//:Frameworks",
            linkoptsL = "@macos_sdk_14.4//:usr_lib",
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
