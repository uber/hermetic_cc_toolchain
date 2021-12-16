[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain

This is a C/C++ toolchain that can (cross-)compile C/C++ programs. It contains
clang-13, musl, glibc (versions 2-2.33, selectable), all in a ~40MB package.
Read
[here](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
about zig-cc; the rest of the README will present how to use this toolchain
from Bazel.

# Usage

Add this to your `WORKSPACE`:

```
BAZEL_ZIG_CC_VERSION = "v0.4.0-rc2"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "3fd0a8ed10adaa49cdb709a9ecb05990c9762849f6098412e205e3a2260fecc4",
    strip_prefix = "bazel-zig-cc-{}".format(BAZEL_ZIG_CC_VERSION),
    urls = ["https://git.sr.ht/~motiejus/bazel-zig-cc/archive/{}.tar.gz".format(BAZEL_ZIG_CC_VERSION)],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_register_toolchains = "register_toolchains")

zig_register_toolchains(register = [
    "x86_64-linux-gnu.2.28",
    "x86_64-macos-gnu",
])
```

The snippet above will download the zig toolchain and register it for the
following platforms:

- `x86_64-linux-gnu.2.28` for `["@platforms//os:linux", "@platforms//cpu:x86_64"]`.
- `x86_64-macos-gnu` for `["@platforms//os:macos", "@platforms//cpu:x86_64"]`.

Note that both Go and Bazel naming schemes are accepted. For convenience with
Go, the following Go-style toolchain aliases are created:

|Bazel (zig) name |Go name|
--- | ---
|`x86_64`|`amd64`|
|`aarch64`|`arm64`|
|`macos`|`darwin`|

For example, the toolchain `linux_amd64_gnu` is aliased to
`x86_64-linux-gnu.2.28`. To find out which toolchains can be registered or
used, run:

```
$ bazel query @zig_sdk//... | sed -En '/.*_toolchain$/ s/.*:(.*)_toolchain$/\1/p'
```

## Compiling OS X executables

MacOS SDK (`--sysroot`) may be necessary. Read [Jakub's comment][sysroot] about
it. This section will be expanded once yours truly understands more about the
requirements and limitations of linking on OSX.

# Known Issues

## using glibc 2.27 or older

**Severity: Low**

Task: [ziglang/zig #9485 glibc 2.27 or older: fcntl64 not found, but zig's glibc headers refer it](https://github.com/ziglang/zig/issues/9485)

Background: when glibc 2.27 or older is selected, it may miss `fcntl64`. A
workaround is applied for `x86_64`, but not for aarch64. The same workaround
may apply to aarch64, but the author didn't find a need to test it (yet).

# Closed issues

- [ziglang/zig misplaced relocated glibc stubs (pthread_sigmask) #7667](https://github.com/ziglang/zig/issues/7667) (CLOSED, thanks mjonaitis and andrewrk)
- [ziglang/zig macho: fail if requested -framework is not found #10312](https://github.com/ziglang/zig/pull/10312) (CLOSED, thanks kubkon)
- [ziglang/zig [darwin aarch64 cgo] regression #10299](https://github.com/ziglang/zig/issues/10299) (CLOSED, thanks kubkon)
- [ziglang/zig [darwin x86_64 cgo] regression #10297](https://github.com/ziglang/zig/issues/10297) (CLOSED, thanks kubkon)
- [ziglang/zig #9431 FileNotFound when compiling macos](https://github.com/ziglang/zig/issues/9431) (CLOSED, thanks andrewrk)
- [rules/go #2894 Per-arch_target linker flags](https://github.com/bazelbuild/rules_go/issues/2894) (CLOSED, thanks mjonaitis)
- [ziglang/zig #7915 ar-compatible command for zig cc](https://github.com/ziglang/zig/issues/7915) (CLOSED, thanks andrewrk)
- [ziglang/zig #7917 [meta] better c/c++ toolchain compatibility](https://github.com/ziglang/zig/issues/7917) (CLOSED, thanks andrewrk)
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050) (CLOSED, thanks kubkon)
- [golang/go #46644 cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644) (CLOSED, thanks kubkon)
- [ziglang/zig #9139 zig c++ hanging when compiling in parallel](https://github.com/ziglang/zig/issues/9139) (CLOSED, thanks andrewrk)

# Testing

## linux cgo + glibc 2.28

```
$ bazel build --platforms @io_bazel_rules_go//go/toolchain:linux_amd64_cgo //test:hello
$ file bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/hello_/hello
bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/hello_/hello: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.0.0, Go BuildID=redacted, with debug_info, not stripped
```

## linux cgo + musl

```
$ bazel build \
    --platforms @io_bazel_rules_go//go/toolchain:linux_amd64_cgo \
    --extra_toolchains @zig_sdk//:linux_amd64_musl_toolchain //test:hello
...
$ file ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/hello_/hello
../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/hello_/hello: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=redacted, with debug_info, not stripped
$ ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/hello_/hello
hello, world
```

## macos cgo

```
$ bazel build --platforms @io_bazel_rules_go//go/toolchain:darwin_amd64_cgo //test:hello
...
$ file bazel-bin/test/hello_/hello
bazel-bin/test/hello_/hello: Mach-O 64-bit x86_64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>
```

## Transient docker environment

```
$ docker run -e CC=/usr/bin/false -ti --rm -v $(pwd):/x -w /x debian:bullseye-slim
# apt update && apt install direnv git -y
# . .envrc
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

# Future & Roadmap

This section lists things that I think will happen at some point: either by
myself, or my colleagues, or outside contributors.

* Move Zig cache path to bazel root, so `bazel clean --expunge` clears the zig
  cache.
* Provide a way to specify alternative URLs for the zig toolchain (currently
  zig is downloaded from jakstys.lt, which is nuts).
* Rename `@zig_sdk//:<toolchain>_toolchain` to
  `@zig_sdk//toolchain:<toolchain>` or similar; so the user-facing targets are
  in their own namespace.
* Provide a way to specify sysroot for Darwin (OSX). See [#Compiling OS X
  executables](#compiling-os-x-executables) for an ongoing discussion.

# Questions & Contributions

Project's mailing list is [~motiejus/bazel-zig-cc][mailing-list]. The mailing
list is used for:

- announcements (I am aiming to send an email with every release).
- user discussions.
- raising issues.
- contributions.

I will generally respond to emails about issues. I may even be able to fix
them. However, no promises: you are much more likely (and welcome!) to get it
fixed by submitting a patch.

To contribute, send your patches to the mailing list, as described in
[git-send-email.io][git-send-email] or via [Sourcehut web UI][video].

Copyright is retained by the contributors.

# Thanks

Many thanks to Adam Bouhenguel and his [bazel-zig-cc][ajbouh], the parent of
this repository. Also, the Zig team for making this all possible and handling
the issues promptly.

[mailing-list]: https://lists.sr.ht/~motiejus/bazel-zig-cc
[ajbouh]: https://github.com/ajbouh/bazel-zig-cc/
[git-send-email]: https://git-send-email.io/
[video]: https://spacepub.space/w/no6jnhHeUrt2E5ST168tRL
[sysroot]: https://github.com/ziglang/zig/issues/10299#issuecomment-989153750
