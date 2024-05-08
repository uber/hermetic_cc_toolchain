VERSION = "0.12.0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "754f1029484079b7e0ca3b913a0a2f2a6afd5a28990cb224fe8845e72f09de63",
    "linux-x86_64": "c7ae866b8a76a568e2d5cfd31fe89cdb629bdd161fdd5018b29a4a0a17045cad",
    "macos-aarch64": "294e224c14fd0822cfb15a35cf39aa14bd9967867999bf8bdfe3db7ddec2a27f",
    "macos-x86_64": "4d411bf413e7667821324da248e8589278180dbc197f4f282b7dbb599a689311",
    "windows-aarch64": "04c6b92689241ca7a8a59b5f12d2ca2820c09d5043c3c4808b7e93e41c7bf97b",
    "windows-x86_64": "2199eb4c2000ddb1fba85ba78f1fcf9c1fb8b3e57658f6a627a8e513131893f5",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
