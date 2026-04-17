VERSION = "0.16.0"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17",
    "linux-x86_64": "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00",
    "macos-aarch64": "b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489",
    "macos-x86_64": "0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7",
    "windows-aarch64": "aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef",
    "windows-x86_64": "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e",
}

# Official recommended version. Should use this when we have a usable release.
# As of 0.14.x, the URL format changed from zig-{os}-{arch}-{version} to
# zig-{arch}-{os}-{version}. We use {host_platform_url} which is arch-os order.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform_url}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform_url}-{version}.{_ext}"
