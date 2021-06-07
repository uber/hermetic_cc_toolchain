cc_binary(
    name = "hello",
    srcs = ["hello.cpp"],
    target_compatible_with = select({
        "@platforms//os:linux": ["@com_github_ziglang_zig//:musl"],
        "//conditions:default": [],
    }),
)

cc_binary(
    name = "exception",
    srcs = ["exception.cpp"],
)
