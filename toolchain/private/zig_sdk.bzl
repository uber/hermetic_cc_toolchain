VERSION = "0.12.0-dev.2631+3069669bc"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "ea6bd76d5de66a39a2c36286fe96a02c37ae7956924bd9e45879facd3a76ebab",
    "linux-x86_64": "fcc7d3e6b69c129d755653b3a7b4efc49fe2f7cee535dadc99999be7416977e7",
    "macos-aarch64": "23ddbde196c4a62de96bf671306bade8454ee776f0d675cb5fc8bfd38f63a22e",
    "macos-x86_64": "64268cb562d2a89c86c51f3c23d82a27690741e77fd980962a1b282b98adc5a4",
    "windows-x86_64": "5216ceda34a7133117bf54fb857d5d1cb47f0f3b834172ee9e707621e2b9d2b3",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
