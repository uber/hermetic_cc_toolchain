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
BAZEL_ZIG_CC_VERSION = "v0.6.1"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "6969858b7f142a0629c61aea4338fca1c81f4e137892464a96bfe9a42ed74821",
    strip_prefix = "bazel-zig-cc-{}".format(BAZEL_ZIG_CC_VERSION),
    urls = ["https://git.sr.ht/~motiejus/bazel-zig-cc/archive/{}.tar.gz".format(BAZEL_ZIG_CC_VERSION)],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_toolchains = "toolchains")

zig_toolchains()
```

>   ### zig sdk download control
>
>   If you are using this in production, you probably want more control over
>   where the zig sdk is downloaded from:
>   ```
>   zig_register_toolchains(
>       version = "<...>",
>       url_formats = [
>           "https://example.internal/zig/zig-{host_platform}-{version}.tar.xz",
>       ],
>       host_platform_sha256 = { ... },
>   )
>   ```

And this to `.bazelrc`:

```
build --incompatible_enable_cc_toolchain_resolution
```

The snippets above will download the zig toolchain and make the bazel
toolchains available for registration and usage.

The next steps depend on your use case.

## I want to manually build a single target with a specific zig cc toolchain

You may explicitly request Bazel to use a specific toolchain (compatible with
the specified platform). For example, if you wish to compile a specific binary
(or run tests) on linux/amd64/musl, you may specify:

```
bazel build \
    --platforms @zig_sdk//platform:linux_arm64 \
    --extra_toolchains @zig_sdk//toolchain:linux_arm64_musl \
    //test/go:go
```

This registers the toolchain `@zig_sdk//toolchain:linux_arm64_musl` for linux
arm64 targets. This toolchains links code statically with musl. We also specify
that we want to build //test/go:go for linux arm64.

## I want to use zig cc as the default compiler

Replace the call to `zig_register_toolchains` with
```
register_toolchains(
    "@zig_sdk//toolchain:linux_amd64_gnu.2.19",
    "@zig_sdk//toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//toolchain:darwin_amd64",
    "@zig_sdk//toolchain:darwin_arm64",
)
```

The snippets above will download the zig toolchain and register it for the
following configurations:

- `toolchain:linux_amd64_gnu.2.19` for `["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:unconstrained"]`.
- `toolchain:linux_arm64_gnu.2.28` for `["@platforms//os:linux", "@platforms//cpu:aarch64", "@zig_sdk//libc:unconstrained"]`.
- `toolchain:darwin_arm64` for `["@platforms//os:macos", "@platforms//cpu:x86_64"]`.
- `toolchain:darwin_arm64` for `["@platforms//os:macos", "@platforms//cpu:aarch64"]`.

>   ### Naming
>
>   Both Go and Bazel naming schemes are accepted. For convenience with
>   Go, the following Go-style toolchain aliases are created:
>
>   |Bazel (zig) name | Go name  |
>   |---------------- | -------- |
>   |`x86_64`         | `amd64`  |
>   |`aarch64`        | `arm64`  |
>   |`macos`          | `darwin` |
>
>   For example, the toolchain `linux_amd64_gnu.2.28` is aliased to
>   `x86_64-linux-gnu.2.28`. To find out which toolchains can be registered or
>   used, run:
>
>   ```
>   $ bazel query @zig_sdk//toolchain/...
>   ```

>   ### Disabling the default bazel cc toolchain
>
>   It may be useful to disable the default toolchain that bazel configures for
>   you, so that configuration issues can be caught early on:
>
>   .bazelrc
>   ```
>   build:zig_cc --action_env BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1
>   ```
>
>   This is not documented in bazel, so use at your own peril.

## I want to start using the zig cc toolchain gradually

You can register your zig cc toolchains under a config in your .bazelrc
```
build:zig_cc --extra_toolchains @zig_sdk//toolchain:linux_amd64_gnu.2.19
build:zig_cc --extra_toolchains @zig_sdk//toolchain:linux_arm64_gnu.2.28
build:zig_cc --extra_toolchains @zig_sdk//toolchain:darwin_amd64
build:zig_cc --extra_toolchains @zig_sdk//toolchain:darwin_arm64
```

Then for your builds/tests you need to specify that the `zig_cc` config
should be used:
```
bazel build --config zig_cc //test/go:go
```

You can build a target for a different platform like so:
```
bazel build --config zig_cc \
    --platforms @zig_sdk//platform:linux_arm64 \
    //test/go:go
```

## I want to use zig to build targets for multiple libc variants

If you have targets that need to be build with different glibc versions or with
musl, you can register a linux toolchain declared under `libc_aware/toolchains`.
It will only be selected when building for a specific libc version. For example

- `libc_aware/toolchain:linux_amd64_gnu.2.19` for `["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:gnu.2.19"]`.
- `libc_aware/toolchain:linux_amd64_gnu.2.28` for `["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:gnu.2.28"]`.
- `libc_aware/toolchain:x86_64-linux-musl` for `["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:musl"]`.

With these toolchains registered, you can build a project for a specific libc
aware platform:
```
$ bazel build --platforms @zig_sdk//libc_aware/platform:linux_amd64_gnu.2.19 //test/go:go
$ bazel build --platforms @zig_sdk//libc_aware/platform:linux_amd64_gnu.2.28 //test/go:go
$ bazel build --platforms @zig_sdk//libc_aware/platform:linux_amd64_musl //test/go:go
```

You can see the list of libc aware toolchains and platforms by running:
```
$ bazel query @zig_sdk//libc_aware/toolchain/...
$ bazel query @zig_sdk//libc_aware/platform/...
 ```

This is especially useful if you are relying on [transitions][transitions], as
transitioning `extra_platforms` will cause your host tools to be rebuilt with
the specific libc version, which takes time, and your host may not be able to
run them.

The `@zig_sdk//libc:variant` constraint is used to select a matching toolchain.
If you are using your own platform definitions, add a `@zig_sdk//libc:variant`
constraint to them. See the list of available values:
```
$ bazel query "attr(constraint_setting, @zig_sdk//libc:variant, @zig_sdk//...)"
```

`@zig_sdk//libc:unconstrained` is a special value that indicates that no value
for the constraint is specified. The non libc aware linux toolchains are only
compatible with this value to prevent accidental silent fallthrough to them.

# UBSAN and "SIGILL: Illegal Instruction"

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
## Transient docker environment

First of all, make sure that your kernel is configured to run arm64 binaries.
You can either `apt install qemu-user-static binfmt-support`; this should setup
`binfmt_misc` to handle arm64 binaries. Or you can use this handy dockerized
script `docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`.

```
$ docker run -e CC=/usr/bin/false -ti --rm -v $(git rev-parse --show-toplevel):/x -w /x debian:bullseye-slim
# dpkg --add-architecture arm64 && apt update && apt install -y direnv git shellcheck libc6:arm64
# . .envrc
# ./ci/test
# ./ci/lint
```

See `ci/test` for how tests are run.

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
[transitions]: https://docs.bazel.build/versions/main/skylark/config.html#user-defined-transitions
