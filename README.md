[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain

This is a C/C++ toolchain that can (cross-)compile C/C++ programs. It contains
clang-13, musl, glibc (versions 2-2.34, selectable), all in a ~40MB package.
Read
[here](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
about zig-cc; the rest of the README will present how to use this toolchain
from Bazel.

# Usage

Add this to your `WORKSPACE`:

```
BAZEL_ZIG_CC_VERSION = "v0.4.4"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "ad6384b4d16ebb3e5047df6548a195e598346da84e5f320250beb9198705ac81",
    strip_prefix = "bazel-zig-cc-{}".format(BAZEL_ZIG_CC_VERSION),
    urls = ["https://git.sr.ht/~motiejus/bazel-zig-cc/archive/{}.tar.gz".format(BAZEL_ZIG_CC_VERSION)],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_register_toolchains = "register_toolchains")

zig_register_toolchains()
```

And this to `.bazelrc`:

```
build --incompatible_enable_cc_toolchain_resolution
build --extra_toolchains @zig_sdk//:linux_amd64_gnu.2.19_toolchain
build --extra_toolchains @zig_sdk//:linux_arm64_gnu.2.28_toolchain
build --extra_toolchains @zig_sdk//:darwin_amd64_toolchain
build --extra_toolchains @zig_sdk//:darwin_arm64_toolchain
```

The snippets above will download the zig toolchain and register it for the
following platforms:

- `x86_64-linux-gnu.2.19` for `["@platforms//os:linux", "@platforms//cpu:x86_64"]`.
- `x86_64-linux-gnu.2.28` for `["@platforms//os:linux", "@platforms//cpu:arm64"]`.
- `x86_64-macos-gnu` for `["@platforms//os:macos", "@platforms//cpu:x86_64"]`.
- `aarch64-macos-gnu` for `["@platforms//os:macos", "@platforms//cpu:arm64"]`.

Note that both Go and Bazel naming schemes are accepted. For convenience with
Go, the following Go-style toolchain aliases are created:

|Bazel (zig) name |Go name|
--- | ---
|`x86_64`|`amd64`|
|`aarch64`|`arm64`|
|`macos`|`darwin`|

For example, the toolchain `linux_amd64_gnu.2.28` is aliased to
`x86_64-linux-gnu.2.28`. To find out which toolchains can be registered or
used, run:

```
$ bazel query @zig_sdk//... | grep _toolchain$
```

## Specifying non-default toolchains (and not registering at all)

You may explicitly request Bazel to use a specific toolchain, even though one
is registered using `--extra_toolchains <toolchain>` flag. For example, if you
wish to compile a specific binary (or run tests) using musl on linux/amd64, you
may specify:

```
--extra_toolchains @zig_sdk//:linux_amd64_musl_toolchain
```

As an extension to this, you may not register the toolchains at all:

```
zig_register_toolchains()
```

In that case, you will need to specify the `--extra_toolchains <toolchain>`
command-line argument. Otherwise Bazel will use the default one -- the host
toolchain.

## UBSAN and "SIGILL: Illegal Instruction"

`zig cc` differs from "mainstream" compilers by [enabling UBSAN by
default][ubsan1]. Which means your program may compile successfully and crash
with:

```
SIGILL: illegal instruction
```

This is by design: it encourages program authors to fix the undefined behavior.
There are [many ways][ubsan2] to find the undefined behavior.

# Known Issues In bazel-zig-cc

These are the things you may stumble into when using bazel-zig-cc. I am
unlikely to implement them any time soon, but patches implementing those will
be accepted. See [Questions & Contributions](#questions-amp-contributions) on
how to contribute.

## Zig cache

Currently zig cache is in `$HOME`, so `bazel clean --expunge` does not clear
the zig cache. Zig's cache should be stored somewhere in the project's path.

## Alternative download URLs

Currently zig is downloaded from
[dl.jakstys.lt/zig](https://dl.jakstys.lt/zig/), which is nuts. One should
provide a way to specify alternative URLs for the zig toolchain.

## Toolchain and platform target locations

The path to Bazel toolchains is `@zig_sdk//:<toolchain>_toolchain`. It should
be moved to `@zig_sdk//toolchain:<toolchain>` or similar; so the user-facing
targets are in their own namespace.

Likewise, platforms are `@zig_sdk//:<platform>_platform`, and should be moved
to `@zig_sdk//:platform:<platform>`.

## OSX: sysroot

For non-trivial programs (and for all darwin/arm64 cgo programs) MacOS SDK may
be necessary. Read [Jakub's comment][sysroot] about it. Support for OSX sysroot
is currently not implemented.

## OSX: different OS targets (Catalina -- Monterey)

[Zig 0.9.0](https://ziglang.org/download/0.9.0/release-notes.html#macOS) may
target macos.10 (Catalina), macos.11 (Big Sur) or macos.12 (Monterey). It
currently targets the lowest version, without ability to change it.

# Known Issues In Upstream

This section lists issues that I've stumbled into when using `zig cc`, and is
outside of bazel-zig-cc's control.

## using glibc 2.27 or older

**Severity: Low**

Task: [ziglang/zig #9485 glibc 2.27 or older: fcntl64 not found, but zig's glibc headers refer it](https://github.com/ziglang/zig/issues/9485)

Background: when glibc 2.27 or older is selected, it may miss `fcntl64`. A
workaround is applied for `x86_64`, but not for aarch64. The same workaround
may apply to aarch64, but the author didn't find a need to test it (yet).

# Closed Upstream Issues

- [ziglang/zig #10386 zig cc regression in 0.9.0](https://github.com/ziglang/zig/issues/10386)(CLOSED, thanks Xavier)
- [ziglang/zig #10312 macho: fail if requested -framework is not found](https://github.com/ziglang/zig/pull/10312) (CLOSED, thanks kubkon)
- [ziglang/zig #10299 [darwin aarch64 cgo] regression](https://github.com/ziglang/zig/issues/10299) (CLOSED, thanks kubkon)
- [ziglang/zig #10297 [darwin x86_64 cgo] regression](https://github.com/ziglang/zig/issues/10297) (CLOSED, thanks kubkon)
- [ziglang/zig #9431 FileNotFound when compiling macos](https://github.com/ziglang/zig/issues/9431) (CLOSED, thanks andrewrk)
- [ziglang/zig #9139 zig c++ hanging when compiling in parallel](https://github.com/ziglang/zig/issues/9139) (CLOSED, thanks andrewrk)
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050) (CLOSED, thanks kubkon)
- [ziglang/zig #7917 [meta] better c/c++ toolchain compatibility](https://github.com/ziglang/zig/issues/7917) (CLOSED, thanks andrewrk)
- [ziglang/zig #7915 ar-compatible command for zig cc](https://github.com/ziglang/zig/issues/7915) (CLOSED, thanks andrewrk)
- [ziglang/zig #7667 misplaced relocated glibc stubs (pthread_sigmask)](https://github.com/ziglang/zig/issues/7667) (CLOSED, thanks mjonaitis and andrewrk)
- [rules/go #2894 Per-arch_target linker flags](https://github.com/bazelbuild/rules_go/issues/2894) (CLOSED, thanks mjonaitis)
- [golang/go #46644 cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644) (CLOSED, thanks kubkon)

# Testing

## build & run linux cgo + glibc

```
$ bazel build --platforms @zig_sdk//:linux_amd64_platform //test/go:go
$ file bazel-out/k8-opt-ST-d17813c235ce/bin/test/go/go_/go
bazel-out/k8-opt-ST-d17813c235ce/bin/test/go/go_/go: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.0.0, Go BuildID=redacted, with debug_info, not stripped
$ bazel-out/k8-opt-ST-d17813c235ce/bin/test/go/go_/go
hello, world
```

## test linux cgo + musl on arm64 (under qemu-aarch64)

```
$ bazel test \
    --run_under=qemu-aarch64-static \
    --platforms @zig_sdk//:linux_arm64_platform \
    --extra_toolchains @zig_sdk//:linux_arm64_musl_toolchain //test/...
...
INFO: Build completed successfully, 10 total actions
//test/go:go_test                                                        PASSED in 0.2s
```

## macos cgo

```
$ bazel build --platforms @zig_sdk//:darwin_amd64_platform //test/go:go
...
$ file bazel-out/k8-opt-ST-d17813c235ce/bin/test/go/go_/go
bazel-out/k8-opt-ST-d17813c235ce/bin/test/go/go_/go: Mach-O 64-bit x86_64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE|HAS_TLV_DESCRIPTORS>
```

## Transient docker environment

```
$ docker run -e CC=/usr/bin/false -ti --rm -v $(pwd):/x -w /x debian:bullseye-slim
# apt update && apt install direnv git -y
# . .envrc
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

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
[ubsan1]: https://github.com/ziglang/zig/issues/4830#issuecomment-605491606
[ubsan2]: https://github.com/ziglang/zig/issues/5163
