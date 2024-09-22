load("@hermetic_cc_toolchain//toolchain:defs.bzl", "macos_sdk", zig_toolchains = "toolchains")

def _toolchains_impl(ctx):
    zig_toolchains(
        macos_sdks = [
            macos_sdk(
              version = "14.4",
              urls = [ "https://github.com/chrisirhc/macos-cltools/releases/download/v0.0.1-dev/CLTools14.4-v0.0.1-dev.tar.gz" ],
              sha256 = "84e699997e262b3ab5524b7bf91609011d2c7e69af6a6ff018b6eaef8a0a5dee",
              strip_prefix = "Payload/Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk",
              # Ruby.framework contains recursive symlinks that break native.glob, so delete them.
              delete_paths = [
                'System/Library/Frameworks/Ruby.framework',
                # 'System/Library/Frameworks/Ruby.framework/Headers/ruby',
                # 'System/Library/Frameworks/Ruby.framework/Versions/Current/Headers/ruby',
                # 'System/Library/Frameworks/Ruby.framework/Versions/2.6/Headers/ruby',
            ],
            )
        ],
    )

toolchains = module_extension(implementation = _toolchains_impl)
