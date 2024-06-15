load("@hermetic_cc_toolchain//toolchain:defs.bzl", "macos_sdk", zig_toolchains = "toolchains")

def _toolchains_impl(ctx):
    zig_toolchains(
        macos_sdks = [
            macos_sdk(
              version = "14.2",
              urls = [ "https://github.com/hexops/xcode-frameworks/archive/122b43323db27b2082a2d44ed2121de21c9ccf75.zip" ],
              sha256 = "e774c140fe476e7a030aefb6f782e58ed79a18d0223bb88fee6a89d6d6cf8d30",
              # strip_prefix = "xcode-frameworks-122b43323db27b2082a2d44ed2121de21c9ccf75",
            )
        ],
    )

toolchains = module_extension(implementation = _toolchains_impl)
