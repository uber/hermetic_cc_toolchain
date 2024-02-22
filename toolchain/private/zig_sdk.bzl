VERSION = "0.12.0-dev.2824+0b7af2563"

HOST_PLATFORM_SHA256 = {
    "linux-aarch64": "b142b8a62297c88d38fad10b95c7247606b0c9fe16cf463d75dfe10fb3269c82",
    "linux-x86_64": "5f9415bd4a6419245be36888b825683f001cdb2d6ad08c60dac85b0a1f39d5aa",
    "macos-aarch64": "85fef6c6bd4f169a0883b4b39896236d37d1957e7ee65eb8a6849387dcb9febd",
    "macos-x86_64": "efe930a9b0765655f5dfc9592fea73bc512888734607686bc9bb1ed3a407714d",
    "windows-aarch64": "2814c31b73fccaf4cfa2d33b56677189bba1e7d450d2bcfa63e9ffbe0d557967",
    "windows-x86_64": "401b627233d8170ff7e2751c69ac6c45bc74986e7e7f3fabd97a07176b312169",
}

# Official recommended version. Should use this when we have a usable release.
URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"

# Caution: nightly releases are purged from ziglang.org after ~90 days. Use the
# Bazel mirror or your own.
URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"
