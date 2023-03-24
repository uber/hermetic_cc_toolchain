[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain

This is a C/C++ toolchain that can (cross-)compile C/C++ programs. It contains
clang-15, musl, glibc 2-2.34, all in a ~40MB package. Read
[here](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
about zig-cc; the rest of the README will present how to use this toolchain
from Bazel.

Configuring toolchains in Bazel is complex, under-documented, and fraught with
peril. I, the co-author of bazel-zig-cc, am still confused on how this all
works, and often wonder why it works at all. That aside, we made the our best
effort to make bazel-zig-cc usable for your C/C++/CGo projects, with as many
guardrails as we could install.

While copy-pasting the code in your project, attempt to read and understand the
text surrounding the code snippets. This will save you hours of head
scratching, I promise.

# Usage

Add this to your `WORKSPACE`:

```
BAZEL_ZIG_CC_VERSION = "v1.0.1"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "e9f82bfb74b3df5ca0e67f4d4989e7f1f7ce3386c295fd7fda881ab91f83e509",
    strip_prefix = "bazel-zig-cc-{}".format(BAZEL_ZIG_CC_VERSION),
    urls = [
        "https://mirror.bazel.build/github.com/uber/bazel-zig-cc/releases/download/{0}/{0}.tar.gz".format(BAZEL_ZIG_CC_VERSION),
        "https://github.com/uber/bazel-zig-cc/releases/download/{0}/{0}.tar.gz".format(BAZEL_ZIG_CC_VERSION),
    ],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_toolchains = "toolchains")

# version, url_formats and host_platform_sha256 are optional for those who
# want to control their Zig SDK version.
zig_toolchains(
    version = "<...>",
    url_formats = [
        "https://example.org/zig/zig-{host_platform}-{version}.{_ext}",
    ],
    host_platform_sha256 = { ... },
)
```

And this to `.bazelrc`:

```
build --incompatible_enable_cc_toolchain_resolution
```

The snippets above will download the zig toolchain and make the bazel
toolchains available for registration and usage. If you do nothing else, this
may work. The `.bazelrc` snippet instructs Bazel to use the registered "new
kinds of toolchains". All above are required regardless of how wants to use it.
The next steps depend on how one wants to use bazel-zig-cc. The descriptions
below is a gentle introduction to C++ toolchains from "user's perspective" too.

## Use case: manually build a single target with a specific zig cc toolchain

This option is least disruptive to the workflow compared to no hermetic C++
toolchain, and works best when trying out or getting started with bazel-zig-cc
for a subset of targets.

To request Bazel to use a specific toolchain (compatible with the specified
platform) for build/tests/whatever on linux-amd64-musl, do:

```
bazel build \
    --platforms @zig_sdk//platform:linux_arm64 \
    --extra_toolchains @zig_sdk//toolchain:linux_arm64_musl \
    //test/go:go
```

There are a few things going on here, let's try to dissect them.

### Option `--platforms @zig_sdk//platform:linux_arm64`

Specifies that the our target platform is `linux_arm64`, which resolves into:

```
$ bazel query --output=build @zig_sdk//platform:linux_arm64
platform(
  name = "linux_arm64",
  generator_name = "linux_arm64",
  generator_function = "declare_platforms",
  generator_location = "platform/BUILD:7:18",
  constraint_values = ["@platforms//os:linux", "@platforms//cpu:aarch64"],
)
```

`constraint_values` instructs Bazel to be looking for a **toolchain** that is
compatible with (in Bazelspeak, `target_compatible_with`) **all of the**
`["@platforms//os:linux", "@platforms//cpu:aarch64"]`.

### Option `--toolchains=@zig_sdk//toolchain:linux_arm64_musl`

Inspect first (`@platforms//cpu:aarch64` is an alias to
`@platforms//cpu:arm64`):

```
$ bazel query --output=build @zig_sdk//toolchain:linux_arm64_musl
toolchain(
  name = "linux_arm64_musl",
  generator_name = "linux_arm64_musl",
  generator_function = "declare_toolchains",
  generator_location = "toolchain/BUILD:7:19",
  toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
  target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:aarch64", "@zig_sdk//libc:unconstrained"],
  toolchain = "@zig_sdk//:aarch64-linux-musl_cc",
)
```

For a platform to pick up the right toolchain, the platform's
`constraint_values` must be a subset[^1] of the toolchain's
`target_compatible_with`. Since the platform is a subset (therefore,
toolchain's `@zig_sdk//libc:unconstrained` does not matter), this toolchain is
selected for this platform. As a result, `--platforms
@zig_sdk//platform:linux_amd64` causes Bazel to select a toolchain
`@zig_sdk//platform:linux_arm64_musl` (because it satisfies all constraints),
which will compile and link the C/C++ code with musl.

`@zig_sdk//libc:unconstrained` will become important later.

### Same as above, less typing (with `--config`)

Specifying the platform and toolchain for every target may become burdensome,
so they can be put used via `--config`. For example, append this to `.bazelrc`:

```
build:linux_arm64 --platforms @zig_sdk//platform:linux_arm64
build:linux_arm64 --extra_toolchains @zig_sdk//toolchain:linux_arm64_musl
```

And then building to linux-arm64-musl boils down to:

```
bazel build --config=linux_arm64_musl //test/go:go
```

## Use case: always compile with zig cc

Instead of adding the toolchains to `.bazelrc`, they can be added
unconditionally. Append this to `WORKSPACE` after `zig_toolchains(...)`:

```
register_toolchains(
    "@zig_sdk//toolchain:linux_amd64_gnu.2.19",
    "@zig_sdk//toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//toolchain:darwin_amd64",
    "@zig_sdk//toolchain:darwin_arm64",
    "@zig_sdk//toolchain:windows_amd64",
    "@zig_sdk//toolchain:windows_arm64",
)
```

Append this to `.bazelrc`:

```
build --action_env BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1
```

From Bazel's perspective, this is almost equivalent to always specifying
`--extra_toolchains` on every `bazel <...>` command-line invocation. It also
means there is no way to disable the toolchain with the command line. This is
useful if you find bazel-zig-cc useful enough to compile for all of your
targets and tools.

With `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1` Bazel stops detecting the default
host toolchain. Configuring toolchains is complicated enough, and the
auto-detection (read: fallback to non-hermetic toolchain) is a footgun best
avoided. This option is not documented in bazel, so may break. If you intend to
use the hermetic toolchain exclusively, it won't hurt.

## Use case: zig-cc for targets for multiple libc variants

When some targets need to be build with different libcs (either different
versions of glibc or musl), use a linux toolchain from
`@zig_sdk//libc_aware/toolchains:<...>`. The toolchain will only be selected
when building for a specific libc. For example, in `WORKSPACE`:

```
register_toolchains(
    "@zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.19",
    "@zig_sdk//libc_aware/toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//libc_aware/toolchain:x86_64-linux-musl",
)
```

What does `@zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.19` mean?

```
$ bazel query --output=build @zig_sdk//libc_aware/toolchain:linux_amd64_gnu.2.19 |& grep target
  target_compatible_with = ["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:gnu.2.19"],
```

To see how this relates to the platform:

```
$ bazel query --output=build @zig_sdk//libc_aware/platform:linux_amd64_gnu.2.19 |& grep constraint
  constraint_values = ["@platforms//os:linux", "@platforms//cpu:x86_64", "@zig_sdk//libc:gnu.2.19"],
```

In this case, the platform's `constraint_values` and toolchain's
`target_compatible_with` are identical, causing Bazel to select the right
toolchain for the requested platform. With these toolchains registered, one can
build a project for a specific libc-aware platform; it will select the
appropriate toolchain:

```
$ bazel run --platforms @zig_sdk//libc_aware/platform:linux_amd64_gnu.2.19 //test/c:which_libc
glibc_2.19
$ bazel run --platforms @zig_sdk//libc_aware/platform:linux_amd64_gnu.2.28 //test/c:which_libc
glibc_2.28
$ bazel run --platforms @zig_sdk//libc_aware/platform:linux_amd64_musl //test/c:which_libc
non_glibc
$ bazel run --run_under=file --platforms @zig_sdk//libc_aware/platform:linux_arm64_gnu.2.28 //test/c:which_libc
which_libc: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for GNU/Linux 2.0.0, stripped
```

To the list of libc aware toolchains and platforms:

```
$ bazel query @zig_sdk//libc_aware/toolchain/...
$ bazel query @zig_sdk//libc_aware/platform/...
 ```

Libc-aware toolchains are especially useful when relying on
[transitions][transitions], as transitioning `extra_platforms` will cause the
host tools to be rebuilt with the specific libc version, which takes time; also
the build host may not be able to run them if, say, target glibc version is
newer than on the host. Some tests in this repository (under `test/`) are using
transitions; you may check out how it's done.

The `@zig_sdk//libc:variant` constraint is necessary to select a matching
toolchain. Remember: the toolchain's `target_compatible_with` must be
equivalent or a superset of the platform's `constraint_values`. This is why
both libc-aware platforms and libc-aware toolchains reside in their own
namespace; if we try to mix non-libc-aware to libc-aware, confusion ensues.

To use the libc constraints in the project's platform definitions, add a
`@zig_sdk//libc:variant` constraint to them. See the list of available values:

```
$ bazel query "attr(constraint_setting, @zig_sdk//libc:variant, @zig_sdk//...)"
```

`@zig_sdk//libc:unconstrained` is a special value that indicates that no value
for the constraint is specified. The non libc aware linux toolchains are only
compatible with this value to prevent accidental silent fallthrough to them.
This is a guardrail. Thanks, future me!

# Note: Naming

Both Go and Bazel naming schemes are accepted. For convenience with
Go, the following Go-style toolchain aliases are created:

|Bazel (zig) name | Go name  |
|---------------- | -------- |
|`x86_64`         | `amd64`  |
|`aarch64`        | `arm64`  |
|`macos`          | `darwin` |

For example, the toolchain `linux_amd64_gnu.2.28` is aliased to
`x86_64-linux-gnu.2.28`. To find out which toolchains can be registered or
used, run:

```
$ bazel query @zig_sdk//toolchain/...
```

# Incompatibilities with clang and gcc

`zig cc` is *almost* a drop-in replacement for clang/gcc. This section lists
some of the discovered differences and ways to live with them.

## UBSAN and "SIGILL: Illegal Instruction"

`zig cc` differs from "mainstream" compilers by [enabling UBSAN by
default][ubsan1]. Which means your program may compile successfully and crash
with:

```
SIGILL: illegal instruction
```

This flag encourages program authors to fix the undefined behavior. There are
[many ways][ubsan2] to find the undefined behavior.

# Known Issues In bazel-zig-cc

These are the things you may stumble into when using bazel-zig-cc. I am
unlikely to implement them any time soon, but patches implementing those will
be accepted. See [Questions & Contributions](#questions-amp-contributions) on
how to contribute.

## Zig cache location

Currently zig cache is in `$HOME`, so `bazel clean --expunge` does not clear
the zig cache. Zig's cache should be stored somewhere in the project's path.

## zig cc concurrency

- Bazel spawns up to `nproc` workers.
- For each of those, Go may spawn up to `nproc` processes while compiling.
- Zig may do the same.

... causing explosion of heavy compiler processes. This causes CPU to spike.
Tracked in [ziglang/zig #12101  RFC: -j/--jobs for zig
subcommands](https://github.com/ziglang/zig/issues/12101).

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

**Severity: Medium**

Task: [ziglang/zig #9485 glibc 2.27 or older: fcntl64 not found, but zig's glibc headers refer it](https://github.com/ziglang/zig/issues/9485)

Background: when glibc 2.27 or older is selected, it may miss `fcntl64`. A
workaround is applied for `x86_64`, but not for aarch64. The same workaround
may apply to aarch64, but the author didn't find a need to test it (yet).

In September 2022 the severity has been bumped to Medium, because glibc header
updates cause a lot of churn when upgrading the SDK, when it shouldn't cause
any at all.

Feel free to track [Universal headers][universal-headers] project for a fix.

## Number of libc stubs with Go 1.20+

Until Go 1.19 the number of glibc stubs that needed to be compiled was strictly
controlled. Go 1.20 no longer ships with pre-compiled archive files for the
standard library, and it generates them on the fly, causing many extraneous
libc stubs. Therefore, the initial compilation will take longer until those
stubs are pre-cached.

# Closed Upstream Issues

- [ziglang/zig #12317 Possibility to disable caching for user](https://github.com/ziglang/zig/issues/12317) (CLOSED, thanks andrewrk and motiejus)
- [golang/go #52690 Go linker does not put libc onto the linker line](https://github.com/golang/go/issues/52690) (CLOSED, thanks andrewrk and motiejus)
- [ziglang/zig #10386 zig cc regression in 0.9.0](https://github.com/ziglang/zig/issues/10386) (CLOSED, thanks Xavier)
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

... and more.

# Host Environments

This repository is used on the following (host) platforms:

- `linux_amd64`, a.k.a. `x86_64`.
- `linux_arm64`, a.k.a. `AArch64`.
- `darwin_amd64`, the 64-bit post-PowerPC models.
- `darwin_arm64`, the M1.
- `windows_amd64`, a.k.a. `x64`.

The tests are running (CId) on linux-amd64.

## Transient docker environment

A standalone Docker environment to play with bazel-zig-cc:

```
$ docker run -e CC=/usr/bin/false -ti --rm -v "$PWD:/x" -w /x debian:bullseye-slim
# apt update && apt install --no-install-recommends -y shellcheck ca-certificates python3
# ./ci/lint
# ./ci/launcher
# ./ci/test
```

# Communication

We maintain two channels for comms:
- Github issues and pull requests.
- Slack: `#zig` in bazel.slack.com.

Previously communications were over email; the past archive is in
`mailing-list-archive.mbox`. It can be accessed like this:

    mutt -f -R mailing-list-archive.mbox

# Maintainers

This section lists the driving forces behind bazel-zig-cc. Committers have push
access, maintainers have their areas. Should make it easier to understand our
interests when reading patches or mailing lists.

- Maintainers: Motiejus Jakštys, Laurynas Lubys, Zhongpeng Lin and Sung Yoon
  Whang.
- Committer for Windows: Fabian Hahn. If you make a change that breaks
  Windows, Fabian will find you. Please don't break Windows, so Fabian doesn't
  have to look for you. Instead, send him your patches first.

You may find contact information of the individuals in the commit logs.

# Publicity

This section lists notable uses or mentions of bazel-zig-cc.

- 2023-01-24 [bazel-zig-cc v1.0.0][bazel-zig-cc-v1]: releasing bazel-zig-cc and
  admitting that bazel-zig-cc is used in production to compile all of Uber's
  [Go Monorepo][go-monorepo].
- 2022-11-18 [BazelCon 2022: Making Uber's hermetic C++
  toolchain][bazelcon2022]: Laurynas Lubys presents the story of how this
  repository came into being and how it was used (as of the conference).
- 2022-05-23 [How Zig is used at Uber (youtube)][yt-how-zig-is-used-at-uber]:
  Yours Truly (the author) talks about how bazel-zig-cc came to existence and
  how it's used at Uber in Milan Zig Meetup.
- 2022-05-23 [How Uber uses Zig][how-uber-uses-zig]: text version of the above.
- 2022-03-30 [Google Open Source Peer Bonus Program][google-award] awarded the
  author $250 for bazel-zig-cc.
- 2022-01-13 [bazel-zig-cc building Envoy][zig-cc-envoy].

# Thanks

Many thanks to Adam Bouhenguel and his [bazel-zig-cc][ajbouh], the parent of
this repository. Also, the Zig team for making this all possible and handling
the issues promptly.

[^1]: a [mathematical subset][subset]: both can be equal.

[ajbouh]: https://github.com/ajbouh/bazel-zig-cc/
[sysroot]: https://github.com/ziglang/zig/issues/10299#issuecomment-989153750
[ubsan1]: https://github.com/ziglang/zig/issues/4830#issuecomment-605491606
[ubsan2]: https://github.com/ziglang/zig/issues/5163
[transitions]: https://docs.bazel.build/versions/main/skylark/config.html#user-defined-transitions
[subset]: https://en.wikipedia.org/wiki/Subset
[yt-how-zig-is-used-at-uber]: https://www.youtube.com/watch?v=SCj2J3HcEfc
[how-uber-uses-zig]: https://jakstys.lt/2022/how-uber-uses-zig/
[zig-cc-envoy]: https://github.com/envoyproxy/envoy/issues/19535
[google-award]: https://opensource.googleblog.com/2022/03/Announcing-First-Group-of-Google-Open-Source-Peer-Bonus-Winners-in-2022.html
[go-gc-sections]: https://go-review.googlesource.com/c/go/+/407814
[universal-headers]: https://github.com/ziglang/universal-headers
[bazel-zig-cc-v1]: https://lists.sr.ht/~motiejus/bazel-zig-cc/%3CCAFVMu-rYbf_jDTT4p%3DCS2KV1asdS5Ovo5AyuCwgv2AXr8OOP0g%40mail.gmail.com%3E
[go-monorepo]: https://www.uber.com/blog/go-monorepo-bazel/
[bazelcon2022]: https://www.youtube.com/watch?v=a1jXzx3884g
