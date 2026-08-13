load("@hermetic_cc_toolchain//toolchain:zig_cc_toolchain.bzl", "zig_cc_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load(":defs.bzl", "target_structs", "zig_tool_path")

# Maps the target OS token used by the `sysroot` config (linux/macos/windows)
# to the substring present in every zig target triple for that OS.
_OS_TRIPLE_TOKEN = {
    "linux": "-linux-",
    "macos": "-macos-",
    "windows": "-windows-",
}

def _sysroot_for(zigtarget, sysroots):
    """Return the sysroot config dict for zigtarget's OS, or None."""
    for os_name, cfg in sysroots.items():
        token = _OS_TRIPLE_TOKEN.get(os_name)
        if token and token in zigtarget:
            return cfg
    return None

def declare_cc_toolchains(os, zig_sdk_path, sysroots_json = "{}"):
    exe = ".exe" if os == "windows" else ""
    sysroots = json.decode(sysroots_json) if sysroots_json else {}
    for target_config in target_structs():
        gotarget = target_config.gotarget
        zigtarget = target_config.zigtarget

        cxx_builtin_include_directories = []
        builtin_sysroot = ""

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

        # Optional external sysroot (e.g. a macOS SDK) for this target OS. The
        # sysroot's include dirs are registered as cxx_builtin_include_directories
        # so Bazel's header-inclusion validation accepts headers found there
        # (a plain -idirafter copt would trip "undeclared inclusion"). The
        # --sysroot / -isysroot flags point zig cc at the SDK's libc + frameworks.
        sysroot_cfg = _sysroot_for(zigtarget, sysroots)
        if sysroot_cfg:
            path = sysroot_cfg.get("path", "")
            is_macos = "-macos-" in zigtarget

            # Setting builtin_sysroot makes Bazel (a) resolve the sysroot symlink
            # when validating header inclusions, so headers found under it are
            # exempt from "undeclared inclusion" errors WITHOUT staging the whole
            # SDK as inputs, and (b) substitute %sysroot% in the include dirs
            # below. It also makes Bazel pass `--sysroot=<path>` automatically to
            # compile AND link. On macOS that `--sysroot` reaches zig cc which,
            # being a clang driver, forwards it to ld64 as `-syslibroot` — fine.
            builtin_sysroot = path

            # We suppress Bazel's implicit `--sysroot` flag (see
            # suppress_builtin_sysroot_flag in zig_cc_toolchain.bzl) so it never
            # reaches raw linkers like rust-lld. Instead pass the sysroot to the
            # COMPILER explicitly here, on compile actions only.
            sysroot_copts = []
            sysroot_linkopts = []
            if path:
                sysroot_copts += ["--sysroot", path]
                if is_macos:
                    # zig/clang find the SDK headers & frameworks via -isysroot
                    # on macOS. Also emit it on link: ld64 (through zig's clang
                    # driver on a cc_binary/cc_library CppLink) derives the
                    # framework search root / .tbd reexport chain from -isysroot.
                    # NB: pure zig-cc `-framework` linking of a cross target
                    # (aarch64-macos-none) is still limited — zig resolves the
                    # top .tbd but its absolute /usr/lib reexports aren't
                    # re-rooted at the sysroot (see ziglang/zig#10299). The real
                    # consumers avoid this: rust links use rules_rust's own
                    # rust-lld, and swipl's framework link happens inside cmake.
                    sysroot_copts += ["-isysroot", path]
                    sysroot_linkopts += ["-isysroot", path]

            # Search the SDK include dirs with -idirafter (LOWEST priority, AFTER
            # the compiler's own libc++/libc headers) rather than -I. zig
            # cross-compiling to *-macos-none does NOT derive usr/include from
            # --sysroot/-isysroot, so the dirs must be named explicitly (else
            # `'libc.h' file not found`); but -I would place the SDK's <stdio.h>
            # etc. BEFORE libc++'s wrappers and break C++ (`<cstdio> tried
            # including <stdio.h> but didn't find libc++'s`). -idirafter keeps
            # the SDK as a fallback for Apple-only headers (libc.h, mach/*,
            # frameworks) without shadowing the toolchain's own headers.
            for d in sysroot_cfg.get("include_dirs", []):
                sysroot_copts += ["-idirafter", d]
            sysroot_copts += list(sysroot_cfg.get("copts", []))
            sysroot_linkopts += list(sysroot_cfg.get("linkopts", []))
            copts = copts + sysroot_copts
            linkopts = linkopts + sysroot_linkopts

            # Register the SDK include dirs as cxx_builtin_include_directories
            # for VALIDATION only (exempt SDK headers from "undeclared
            # inclusion"). They are registered in the %sysroot% form ONLY —
            # zig_cc_toolchain.bzl strips %-prefixed entries from the emitted -I
            # flags, so these never shadow libc++ (the search is the -idirafter
            # above). builtin_sysroot resolves the external symlink so the
            # %sysroot% dir matches the .d-recorded header paths
            # (external/.../usr/include/...). Any dir outside `path` is
            # registered literally (it can't be %sysroot%-relative); such a dir
            # WOULD become a -I, so callers should keep include_dirs under path.
            for d in sysroot_cfg.get("include_dirs", []):
                if path and (d == path or d.startswith(path + "/")):
                    cxx_builtin_include_directories = (
                        cxx_builtin_include_directories +
                        ["%sysroot%" + d[len(path):]]
                    )
                else:
                    cxx_builtin_include_directories = (
                        cxx_builtin_include_directories + [d]
                    )

        # We can't pass a list of structs to a rule, so we use json encoding.
        artifact_name_patterns = getattr(target_config, "artifact_name_patterns", [])
        artifact_name_pattern_strings = [json.encode(p) for p in artifact_name_patterns]

        zig_cc_toolchain_config(
            name = zigtarget + "_cc_config",
            target = zigtarget,
            tool_paths = tool_paths,
            cxx_builtin_include_directories = cxx_builtin_include_directories,
            builtin_sysroot = builtin_sysroot,
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
        )

        cc_toolchain(
            name = zigtarget + "_cc",
            toolchain_identifier = zigtarget + "-toolchain",
            toolchain_config = ":%s_cc_config" % zigtarget,
            all_files = "//:{}_all_files".format(zigtarget),
            ar_files = "//:{}_ar_files".format(zigtarget),
            as_files = "//:{}_compiler_files".format(zigtarget),
            compiler_files = "//:{}_compiler_files".format(zigtarget),
            linker_files = "//:{}_linker_files".format(zigtarget),
            dwp_files = "//:empty",
            objcopy_files = "//:empty",
            strip_files = "//:empty",
            supports_param_files = 0,
            visibility = ["//visibility:private"],
        )
