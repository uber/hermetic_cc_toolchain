VERSION = "0.15.2"

HOST_PLATFORM_SHA256 = {
    "aarch64-linux": "958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f",
    "x86_64-linux": "02aa270f183da276e5b5920b1dac44a63f1a49e55050ebde3aecc9eb82f93239",
    "aarch64-macos": "3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b",
    "x86_64-macos": "375b6909fc1495d16fc2c7db9538f707456bfc3373b14ee83fdd3e22b3d43f7f",
    "aarch64-windows": "b926465f8872bf983422257cd9ec248bb2b270996fbe8d57872cca13b56fc370",
    "x86_64-windows": "3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
