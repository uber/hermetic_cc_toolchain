VERSION = "0.17.1"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "a1546d5646eb184437918d6635ca6b762a0e889eac09cef720ee7a1ed3fe7795",
    "linux-x86_64": "3581863e3cbcfd0fce0efc682ce7e9e93da96668a977791d356a26d2a7e9b17a",
    "macos-aarch64": "75f1bc7a1e9852f17ec9a0c1895f767c4ec56d46bc8a834920eece1d0359dd8d",
    "macos-x86_64": "9af07b20319fbd0c92ee46ad23e81d6a782b1aaea2cfb8dcbff35f1d2c7ddbb7",
    "windows-aarch64": "4789895bdb1e312a2ea73b2a7c0a0cc8d2ab62ba6976e834a7c54cf443377c15",
    "windows-x86_64": "b03f477a1943673e02aca0f570e8030dffd536ce1f45cbc4d3326ec31159562e",
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
