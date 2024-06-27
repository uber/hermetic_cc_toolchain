_ZIG_TOOL_PATH = "tools/{zigtarget}/{zig_tool}"

# Zig supports even older glibcs than defined below, but we have tested only
# down to 2.17.
# $ zig targets | jq -r '.glibc[]' | sort -V
_GLIBCS = [
    "2.17",
    "2.18",
    "2.19",
    "2.22",
    "2.23",
    "2.24",
    "2.25",
    "2.26",
    "2.27",
    "2.28",
    "2.29",
    "2.30",
    "2.31",
    "2.32",
    "2.33",
    "2.34",
    "2.35",
    "2.36",
    "2.37",
    "2.38",
]

_INCLUDE_TAIL = [
    "libcxx/include",
    "libcxxabi/include",
    "include",
]

LIBCS = ["musl"] + ["gnu.{}".format(glibc) for glibc in _GLIBCS]

def zig_tool_path(os):
    if os == "windows":
        return _ZIG_TOOL_PATH + ".exe"
    else:
        return _ZIG_TOOL_PATH

def target_structs(macos_sdk_versions):
    ret = []
    for zigcpu, gocpu in (("x86_64", "amd64"), ("aarch64", "arm64")):
        ret.append(_target_windows(gocpu, zigcpu))
        ret.append(_target_linux_musl(gocpu, zigcpu))
        for glibc in _GLIBCS:
            ret.append(_target_linux_gnu(gocpu, zigcpu, glibc))
        for macos_sdk_version in macos_sdk_versions:
            ret.append(_target_macos(gocpu, zigcpu, macos_sdk_version))
    ret.append(_target_wasm())
    return ret

def _target_macos(gocpu, zigcpu, macos_sdk_version):
    macos_sdk_opts = [
        "--sysroot",
        "$(location @macos_sdk_{}//:usr_include)".format(macos_sdk_version),
        "-F",
        "@macos_sdk_{}//:Frameworks".format(macos_sdk_version),
        "-L",
        "@macos_sdk_{}//:usr_lib".format(macos_sdk_version),
    ]

    copts = macos_sdk_opts

    if zigcpu == "aarch64":
        copts.append("-mcpu=apple_m1")

    return struct(
        gotarget = "darwin_{}_sdk.{}".format(gocpu, macos_sdk_version),
        zigtarget = "{}-macos-sdk.{}".format(zigcpu, macos_sdk_version),
        includes = [
          "libc/include/any-macos-any",
        ] + _INCLUDE_TAIL,
        linkopts = macos_sdk_opts,
        dynamic_library_linkopts = ["-Wl,-undefined=dynamic_lookup"],
        supports_dynamic_linker = True,
        cxx_builtin_include_directories = [
          "@macos_sdk_{}//:usr_include".format(macos_sdk_version),
        ],
        sdk_include_files = [
          "@macos_sdk_{}//:Frameworks".format(macos_sdk_version),
          # "@macos_sdk_{}//:usr_include".format(macos_sdk_version),
        ],
        sdk_lib_files = ["@macos_sdk_{}//:usr_lib".format(macos_sdk_version)],
        copts = copts,
        libc = "macos",
        bazel_target_cpu = "darwin",
        constraint_values = [
            "@platforms//os:macos",
            "@platforms//cpu:{}".format(zigcpu),
        ],

        # No longer in upstream zig
        # // https://github.com/ziglang/zig/commit/0e15205521b9a8c95db3c1714dffe3be1df5cda1
        ld_zig_subcmd = None,
        artifact_name_patterns = [
            {
                "category_name": "dynamic_library",
                "prefix": "lib",
                "extension": ".dylib",
            },
        ],
        libc_constraint = "@zig_sdk//libc:macos.{}".format(macos_sdk_version),
        deps = [
            "@macos_sdk_{}//:usr_lib".format(macos_sdk_version),
            "@macos_sdk_{}//:root".format(macos_sdk_version),
        ],
    )

def _target_windows(gocpu, zigcpu):
    return struct(
        gotarget = "windows_{}".format(gocpu),
        zigtarget = "{}-windows-gnu".format(zigcpu),
        includes = [
            "libc/mingw",
            "libunwind/include",
            "libc/include/any-windows-any",
        ] + _INCLUDE_TAIL,
        linkopts = [],
        dynamic_library_linkopts = [],
        # zig cc supports dynamic linking on Windows just fine, but bazel itself doesn't: In order to build and use DLLs
        # properly, one needs to define __declspec(dllexport) and __declspec(dllimport) attributes in headers of shared
        # libraries depending on whether they are being compiled or imported. Bazel doesn't natively support a good way
        # of doing it and the idea of static linking everything is pretty ingrained in how cc_library rules work. On
        # Windows, even the default MSVC cc toolchain doesn't set the supports_dynamic_linker feature and only builds
        # static library by default. Note that you can still build Windows DLLs if you really want to through the
        # cc_binary rule, see the example in the upstream bazel repo in /examples/windows/dll/.
        supports_dynamic_linker = False,
        # Required to compile Go SDK. Otherwise:
        #   zig: error: argument unused during compilation: '-mthreads' [-Werror,-Wunused-command-line-argument]
        copts = ["-Wno-unused-command-line-argument"],
        libc = "mingw",
        bazel_target_cpu = "x64_windows",
        constraint_values = [
            "@platforms//os:windows",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        ld_zig_subcmd = "lld-link",
        artifact_name_patterns = [
            {
                "category_name": "static_library",
                "prefix": "",
                "extension": ".lib",
            },
            {
                "category_name": "dynamic_library",
                # This prefix is an ugly hack around the fact that DLL linking on Windows produces *two* library files:
                # A dll file with the actual shared library, and a lib file withe the necessary import definitions for
                # other targets to link against. Unlike on Linux where you can link against another so file, in order to
                # link against a dll you need to link against its corresponding lib file. However, if we don't set this
                # prefix the generated lib file conflicts with the lib file of a potential static library of the same
                # name. This will then result in "permission denied" linker errors when both linkers try to write to the
                # same file.
                "prefix": "dynamic_",
                "extension": ".dll",
            },
            {
                "category_name": "executable",
                "prefix": "",
                "extension": ".exe",
            },
        ],
    )

def _target_linux_gnu(gocpu, zigcpu, glibc_version):
    glibc_suffix = "gnu.{}".format(glibc_version)

    return struct(
        gotarget = "linux_{}_{}".format(gocpu, glibc_suffix),
        zigtarget = "{}-linux-{}".format(zigcpu, glibc_suffix),
        includes = [
                       "libc/include/{}-linux-gnu".format(zigcpu),
                       "libc/include/generic-glibc",
                   ] +
                   # x86_64-linux-any is x86_64-linux and x86-linux combined.
                   (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []) +
                   (["libc/include/{}-linux-any".format(zigcpu)] if zigcpu != "x86_64" else []) + [
            "libc/include/any-linux-any",
        ] + _INCLUDE_TAIL,
        linkopts = [],
        dynamic_library_linkopts = [],
        supports_dynamic_linker = True,
        copts = [],
        libc = "glibc",
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        libc_constraint = "@zig_sdk//libc:{}".format(glibc_suffix),
        ld_zig_subcmd = "ld.lld",
        artifact_name_patterns = [],
    )

def _target_linux_musl(gocpu, zigcpu):
    return struct(
        gotarget = "linux_{}_musl".format(gocpu),
        zigtarget = "{}-linux-musl".format(zigcpu),
        includes = [
                       "libc/include/{}-linux-musl".format(zigcpu),
                       "libc/include/generic-musl",
                   ] +
                   # x86_64-linux-any is x86_64-linux and x86-linux combined.
                   (["libc/include/x86-linux-any"] if zigcpu == "x86_64" else []) +
                   (["libc/include/{}-linux-any".format(zigcpu)] if zigcpu != "x86_64" else []) + [
            "libc/include/any-linux-any",
        ] + _INCLUDE_TAIL,
        linkopts = [],
        dynamic_library_linkopts = [],
        supports_dynamic_linker = True,
        copts = ["-D_LIBCPP_HAS_MUSL_LIBC", "-D_LIBCPP_HAS_THREAD_API_PTHREAD"],
        libc = "musl",
        bazel_target_cpu = "k8",
        constraint_values = [
            "@platforms//os:linux",
            "@platforms//cpu:{}".format(zigcpu),
        ],
        libc_constraint = "@zig_sdk//libc:musl",
        ld_zig_subcmd = "ld.lld",
        artifact_name_patterns = [],
    )

def _target_wasm():
    return struct(
        gotarget = "wasip1_wasm",
        zigtarget = "wasm32-wasi-musl",
        includes = [
            "libc/include/wasm-wasi-musl",
            "libc/wasi",
        ] + _INCLUDE_TAIL,
        linkopts = [],
        dynamic_library_linkopts = [],
        supports_dynamic_linker = False,
        copts = [],
        libc = "musl",
        bazel_target_cpu = "wasm32",
        constraint_values = [
            "@platforms//os:wasi",
            "@platforms//cpu:wasm32",
        ],
        ld_zig_subcmd = "wasm-ld",
        artifact_name_patterns = [],
    )
