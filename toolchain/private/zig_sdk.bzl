VERSION = "0.14.0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "ab64e3ea277f6fc5f3d723dcd95d9ce1ab282c8ed0f431b4de880d30df891e4f",
    "linux-x86_64": "473ec26806133cf4d1918caf1a410f8403a13d979726a9045b421b685031a982",
    "macos-aarch64": "b71e4b7c4b4be9953657877f7f9e6f7ee89114c716da7c070f4a238220e95d7e",
    "macos-x86_64": "685816166f21f0b8d6fc7aa6a36e91396dcd82ca6556dfbe3e329deffc01fec3",
    "windows-aarch64": "03e984383ebb8f85293557cfa9f48ee8698e7c400239570c9ff1aef3bffaf046",
    "windows-x86_64": "f53e5f9011ba20bbc3e0e6d0a9441b31eb227a97bac0e7d24172f1b8b27b4371",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
