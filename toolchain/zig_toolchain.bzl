load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "artifact_name_pattern",
    "feature",
    "feature_set",
    "flag_group",
    "flag_set",
    "tool",
    "tool_path",
)

all_link_actions = [
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

dynamic_library_link_actions = [
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

compile_and_link_actions = [
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
]

rest_compile_actions = [
    ACTION_NAMES.assemble,
    ACTION_NAMES.cc_flags_make_variable,
    ACTION_NAMES.clif_match,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_codegen,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.lto_backend,
    ACTION_NAMES.preprocess_assemble,
]

def _compilation_mode_features(ctx):
    actions = all_link_actions + compile_and_link_actions + rest_compile_actions

    dbg_feature = feature(
        name = "dbg",
        flag_sets = [
            flag_set(
                actions = actions,
                flag_groups = [
                    flag_group(
                        flags = ["-g", "-fsanitize-undefined-strip-path-components=-1"],
                    ),
                ],
            ),
        ],
    )

    opt_feature = feature(
        name = "opt",
        flag_sets = [
            flag_set(
                actions = actions,
                flag_groups = [
                    flag_group(
                        flags = ["-O2", "-DNDEBUG"],
                    ),
                ],
            ),
        ],
    )

    # fastbuild also gets the strip_debug_symbols flags by default.
    fastbuild_feature = feature(
        name = "fastbuild",
        flag_sets = [
            flag_set(
                actions = actions,
                flag_groups = [
                    flag_group(
                        flags = ["-fno-lto", "-fsanitize-undefined-strip-path-components=-1"],
                    ),
                ],
            ),
        ],
    )

    return [
        dbg_feature,
        opt_feature,
        fastbuild_feature,
    ]

def _zig_cc_toolchain_config_impl(ctx):
    compiler_flags = [
        "-I" + d
        for d in ctx.attr.cxx_builtin_include_directories
    ] + [
        "-no-canonical-prefixes",
        "-Wno-builtin-macro-redefined",
        "-D__DATE__=\"redacted\"",
        "-D__TIMESTAMP__=\"redacted\"",
        "-D__TIME__=\"redacted\"",
    ]

    compile_and_link_flags = feature(
        name = "compile_and_link_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = compile_and_link_actions,
                flag_groups = [
                    flag_group(flags = compiler_flags + ctx.attr.copts),
                ],
            ),
        ],
    )

    link_flag_sets = []

    if ctx.attr.linkopts:
        # if target_config.deps:
        # native.filegroup(name = "target_deps", srcs = ["@macos_sdk_14.2"])
        expanded_linkopts = [ctx.expand_location(linkopt) for linkopt in ctx.attr.linkopts]
        link_flag_sets.append(
            flag_set(
                actions = all_link_actions,
                flag_groups = [flag_group(flags = expanded_linkopts)],
            ),
        )

    if ctx.attr.dynamic_library_linkopts:
        link_flag_sets.append(
            flag_set(
                actions = dynamic_library_link_actions,
                flag_groups = [flag_group(flags = ctx.attr.dynamic_library_linkopts)],
            ),
        )

    default_linker_flags = feature(
        name = "default_linker_flags",
        enabled = True,
        flag_sets = link_flag_sets,
    )

    supports_dynamic_linker = feature(
        name = "supports_dynamic_linker",
        enabled = ctx.attr.supports_dynamic_linker,
    )

    strip_debug_symbols_feature = feature(
        name = "strip_debug_symbols",
        flag_sets = [
            flag_set(
                actions = all_link_actions,
                flag_groups = [
                    flag_group(
                        flags = ["-Wl,-S"],
                        expand_if_available = "strip_debug_symbols",
                    ),
                ],
            ),
        ],
    )

    features = [
        compile_and_link_flags,
        default_linker_flags,
        supports_dynamic_linker,
        strip_debug_symbols_feature,
    ] + _compilation_mode_features(ctx)

    artifact_name_patterns = [
        artifact_name_pattern(**json.decode(p))
        for p in ctx.attr.artifact_name_patterns
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        features = features,
        toolchain_identifier = "%s-toolchain" % ctx.attr.target,
        host_system_name = "local",
        target_system_name = ctx.attr.target_system_name,
        target_cpu = ctx.attr.target_cpu,
        target_libc = ctx.attr.target_libc,
        compiler = ctx.attr.compiler,
        abi_version = ctx.attr.abi_version,
        abi_libc_version = ctx.attr.abi_libc_version,
        tool_paths = [
            tool_path(name = name, path = path)
            for name, path in ctx.attr.tool_paths.items()
        ],
        cxx_builtin_include_directories = ctx.attr.cxx_builtin_include_directories,
        artifact_name_patterns = artifact_name_patterns,
    )

zig_cc_toolchain_config = rule(
    implementation = _zig_cc_toolchain_config_impl,
    attrs = {
        "cxx_builtin_include_directories": attr.string_list(),
        "linkopts": attr.string_list(),
        "dynamic_library_linkopts": attr.string_list(),
        "supports_dynamic_linker": attr.bool(),
        "copts": attr.string_list(),
        "tool_paths": attr.string_dict(),
        "target": attr.string(),
        "target_system_name": attr.string(),
        "target_cpu": attr.string(),
        "target_libc": attr.string(),
        "target_suffix": attr.string(),
        "compiler": attr.string(),
        "abi_version": attr.string(),
        "abi_libc_version": attr.string(),
        "artifact_name_patterns": attr.string_list(),
        "deps": attr.label_list(),
    },
    provides = [CcToolchainConfigInfo],
)
