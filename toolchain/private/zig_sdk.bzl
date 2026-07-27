VERSION = "0.15.2"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "958ed7d1e00d0ea76590d27666efbf7a932281b3d7ba0c6b01b0ff26498f667f",
    "linux-x86_64": "02aa270f183da276e5b5920b1dac44a63f1a49e55050ebde3aecc9eb82f93239",
    "macos-aarch64": "3cc2bab367e185cdfb27501c4b30b1b0653c28d9f73df8dc91488e66ece5fa6b",
    "macos-x86_64": "375b6909fc1495d16fc2c7db9538f707456bfc3373b14ee83fdd3e22b3d43f7f",
    "windows-aarch64": "b926465f8872bf983422257cd9ec248bb2b270996fbe8d57872cca13b56fc370",
    "windows-x86_64": "3a0ed1e8799a2f8ce2a6e6290a9ff22e6906f8227865911fb7ddedc3cc14cb0c",
}

# Zig >=0.14.1 names its release tarballs zig-{arch}-{os}-{version} (arch
# first), whereas older releases used zig-{os}-{arch}-{version}. The download
# URL and archive strip-prefix therefore use the {zig_platform} format var
# (arch-os), while the dicts above stay keyed by {os}-{arch} for the public
# host_platform_sha256 / host_platform_ext override API.

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{zig_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{zig_platform}-{version}.{_ext}"
