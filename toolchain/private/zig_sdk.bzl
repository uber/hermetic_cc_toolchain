VERSION = "0.14.0-dev.3028+cdc9d65b0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "2049eda7a11a4ca251d9d8d2546c6778828edd0940d621805f2b9c56a06c5043",
    "linux-x86_64": "",
    "macos-aarch64": "ea5b85f82fe22d81dc0d2f2f78f59999418e13ac0fb4d2a5fcfc7be1a979cb80",
    "macos-x86_64": "",
    "windows-aarch64": "",
    "windows-x86_64": "1fa65e7110416ea338868f042c457ed4d724c281cb94329436f6c32f3e658854",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
