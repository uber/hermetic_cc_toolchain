VERSION = "0.13.0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "041ac42323837eb5624068acd8b00cd5777dac4cf91179e8dad7a7e90dd0c556",
    "linux-x86_64": "d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea",
    "macos-aarch64": "46fae219656545dfaf4dce12fb4e8685cec5b51d721beee9389ab4194d43394c",
    "macos-x86_64": "8b06ed1091b2269b700b3b07f8e3be3b833000841bae5aa6a09b1a8b4773effd",
    "windows-aarch64": "95ff88427af7ba2b4f312f45d2377ce7a033e5e3c620c8caaa396a9aba20efda",
    "windows-x86_64": "d859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
