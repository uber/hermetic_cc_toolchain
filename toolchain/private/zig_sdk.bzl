VERSION = "0.14.0-dev.3028+cdc9d65b0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "041ac42323837eb5624068acd8b00cd5777dac4cf91179e8dad7a7e90dd0c556",
    "linux-x86_64": "d45312e61ebcc48032b77bc4cf7fd6915c11fa16e4aad116b66c9468211230ea",
    "macos-aarch64": "46fae219656545dfaf4dce12fb4e8685cec5b51d721beee9389ab4194d43394c",
    "macos-x86_64": "5d82aba58eff4221f736bdcfb009df4be186d221532e25cc2380ed41f9aca77f",
    "windows-aarch64": "95ff88427af7ba2b4f312f45d2377ce7a033e5e3c620c8caaa396a9aba20efda",
    "windows-x86_64": "d859994725ef9402381e557c60bb57497215682e355204d754ee3df75ee3c158",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
