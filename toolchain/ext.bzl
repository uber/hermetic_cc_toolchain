load("@hermetic_cc_toolchain//toolchain:defs.bzl", "macos_sdk", zig_toolchains = "toolchains")

def _toolchains_impl(ctx):
    zig_toolchains(
        macos_sdks = [
            macos_sdk(
              version = "14.4",
              urls = [ "https://swcdn.apple.com/content/downloads/14/48/052-59890-A_I0F5YGAY0Y/p9n40hio7892gou31o1v031ng6fnm9sb3c/CLTools_macOSNMOS_SDK.pkg" ],
              sha256 = "6f35bd96401f2a07a8ab8f21321f2706a51d2309da7406fb81fbefd16af3c9d0",
              strip_prefix = "Library/Developer/CommandLineTools/SDKs/MacOSX14.4.sdk",
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
