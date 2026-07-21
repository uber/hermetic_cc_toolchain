# Copyright 2026 Uber Technologies, Inc.
# Licensed under the MIT License

# Tests for the ar wrapper's thin-archive handling.
#
# Zig 0.15's linker could not read thin archives (ziglang/zig#25694):
#     error: unexpected token in LD script: literal: '!<thin>'
# so the toolchain's ar wrapper strips thin-archive requests (the `T`
# modifier and `--thin`) and produces regular archives instead. The strip is
# retained on Zig 0.16 for consistency with the 0.15 line even though the
# upstream bug is fixed there.
#
# ar_thin_request_test checks the workaround: asking the wrapper for a thin
# archive yields a regular archive that links.
#
# thin_archive_canary_test checks upstream behavior with the wrapper
# bypassed: a genuinely thin archive created by raw `zig ar` links fine on
# Zig 0.16 (ziglang/zig#25694 is fixed). If a future Zig regresses
# thin-archive reading, this test fails.

_TEST_DATA = [
    "main.c",
    "member.c",
    "@zig_config//:x86_64-linux-musl_ar_files",
    "@zig_config//:x86_64-linux-musl_compiler_files",
    "@zig_config//:x86_64-linux-musl_linker_files",
    "@zig_config//:zig",
]

# sh_test does not run on Windows CI.
_NOT_ON_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

sh_test(
    name = "ar_thin_request_test",
    srcs = ["thin_archive_test.sh"],
    args = ["wrapper"],
    data = _TEST_DATA,
    env = {"ZIG": "$(rlocationpath @zig_config//:zig)"},
    target_compatible_with = _NOT_ON_WINDOWS,
)

sh_test(
    name = "thin_archive_canary_test",
    srcs = ["thin_archive_test.sh"],
    args = ["raw"],
    data = _TEST_DATA,
    env = {"ZIG": "$(rlocationpath @zig_config//:zig)"},
    target_compatible_with = _NOT_ON_WINDOWS,
)
