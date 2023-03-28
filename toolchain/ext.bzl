load("@hermetic_cc_toolchain//toolchain:defs.bzl", "macos_sdk", zig_toolchains = "toolchains")

def _toolchains_impl(ctx):
    zig_toolchains(
        macos_sdks = [
            macos_sdk(
              version = "13.1",
              urls = [ "https://dl.jakstys.lt/ntpad/x/MacOSX13.1.sdk.tar.zst" ],
              sha256 = "9b65f80a142dfb0b7d295636ad8b8f9b9b3450957f6d101f1076836463e729a9",
            )
        ],
    )

toolchains = module_extension(implementation = _toolchains_impl)
