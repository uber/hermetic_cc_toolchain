[![ci](https://github.com/uber/hermetic_cc_toolchain/actions/workflows/ci.yaml/badge.svg)](https://github.com/uber/hermetic_cc_toolchain/actions/workflows/ci.yaml)

# Hermetic CC toolchain

This is a C/C++ toolchain that can (cross-)compile C/C++ programs on top of
`zig cc`. It contains clang-17, musl, glibc 2.17-2.38, all in a ~40MB package.
Read
[here](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
about zig-cc; the rest of the README will present how to use this toolchain
from Bazel.

Configuring toolchains in Bazel is complex and fraught with peril. We, the team
behind `hermetic_cc_toolchain`, are still confused on how this all works, and
often wonder why it works at all. That aside, we made our best effort to make
`hermetic_cc_toolchain` usable for your C/C++/CGo projects, with as many
guardrails can be installed.

While copy-pasting the code in your project, attempt to read and understand the
text surrounding the code snippets. This will save you hours of head
scratching.

## Project Origin

This repository is cloned from and is based on Adam Bouhenguel's
[bazel-zig-cc][ajbouh], and was later developed at
`sr.ht/~motiejus/bazel-zig-cc`. After a while this repository was moved to [the
Uber GitHub repository](https://github.com/uber) and renamed to
`hermetic_cc_toolchain`.

> **Our special thanks to Adam for coming up with the idea - and creating the
> original version – of `bazel-zig-cc` and publishing it. His idea and work
> helped make the concept of using Zig with Bazel a reality; now we all can
> benefit from it.**

## Usage

Add this to your `WORKSPACE`:

```
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

HERMETIC_CC_TOOLCHAIN_VERSION = "v3.0.0"

http_archive(
    name = "hermetic_cc_toolchain",
    sha256 = "fe00bd126e57a4c3fec4efa620bf074e3d1f1fbd70b75113ca56a010d7a70d93",
    urls = [
        "https://mirror.bazel.build/github.com/uber/hermetic_cc_toolchain/releases/download/{0}/hermetic_cc_toolchain-{0}.tar.gz".format(HERMETIC_CC_TOOLCHAIN_VERSION),
        "https://github.com/uber/hermetic_cc_toolchain/releases/download/{0}/hermetic_cc_toolchain-{0}.tar.gz".format(HERMETIC_CC_TOOLCHAIN_VERSION),
    ],
)

load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

# Plain zig_toolchains() will pick reasonable defaults. See
# toolchain/defs.bzl:toolchains on how to change the Zig SDK version and
# download URL.
zig_toolchains()
```

And this to `.bazelrc` on a Unix-y systems:

```
common --enable_platform_specific_config
build:linux --sandbox_add_mount_pair=/tmp
build:macos --sandbox_add_mount_pair=/var/tmp
build:windows --sandbox_add_mount_pair=C:\Temp
```

The directories can be narrowed down to `/tmp/zig-cache` (Linux),
`/var/tmp/zig-cache` (MacOS) and `C:\Temp\zig-cache` respectively
if it can be ensured they will be created before the invocation of `bazel
build`. See [#83][pr-83] for more context. If a different place is prefferred
for zig cache, set:

```
build --repo_env=HERMETIC_CC_TOOLCHAIN_CACHE_PREFIX=/path/to/cache
build --sandbox_add_mount_pair=/path/to/cache
```

The snippets above will download the zig toolchain and make the bazel
toolchains available for registration and usage. If nothing else is done, this
will work for some minimal use cases. The `.bazelrc` snippet instructs Bazel to
use the registered "new kinds of toolchains". The next steps depend on how one
wants to use `hermetic_cc_toolchain`. The descriptions below is a gentle
introduction to C++ toolchains from "user's perspective" too.

See [examples][examples] for some other recommended `.bazelrc` flags, as well
as how to use `hermetic_cc_toolchain` with bzlmod.

### Use case: manually build a single target with a specific zig cc toolchain

This option is least disruptive to the workflow compared to no hermetic C++
toolchain, and works best when trying out or getting started with
`hermetic_cc_toolchain` for a subset of targets.

To request Bazel to use a specific toolchain (compatible with the specified
platform) for build/tests/whatever on linux-amd64-musl, do:

```
bazel build \
    --platforms @zig_sdk//platform:linux_arm64 \
    --extra_toolchains @zig_sdk//toolchain:linux_arm64_musl \
    //test/go:go
```

There are a few things going on here, let's try to dissect them.

#### Option `--platforms @zig_sdk//platform:linux_arm64`

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

#### Option `--toolchains=@zig_sdk//toolchain:linux_arm64_musl`

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

#### Same as above, less typing (with `--config`)

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

### Use case: always compile with zig cc

Instead of adding the toolchains to `.bazelrc`, they can be added
unconditionally. Append this to `WORKSPACE` after `zig_toolchains(...)`:

```
register_toolchains(
    "@zig_sdk//toolchain:linux_amd64_gnu.2.28",
    "@zig_sdk//toolchain:linux_arm64_gnu.2.28",
    "@zig_sdk//toolchain:darwin_amd64",
    "@zig_sdk//toolchain:darwin_arm64",
    "@zig_sdk//toolchain:windows_amd64",
    "@zig_sdk//toolchain:windows_arm64",
    "@zig_sdk//toolchain:wasip1_wasm",
)
```

Append this to `.bazelrc`:

```
build --action_env BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1
```

From Bazel's perspective, this is almost equivalent to always specifying
`--extra_toolchains` on every `bazel <...>` command-line invocation. It also
means there is no way to disable the toolchain with the command line. This is
useful if you find `hermetic_cc_toolchain` useful enough to compile for all of
your targets and tools.

With `BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1` Bazel stops detecting the default
host toolchain. Configuring toolchains is complicated enough, and the
auto-detection (read: fallback to non-hermetic toolchain) is a footgun best
avoided. This option is not documented in bazel, so may break. If you intend to
use the hermetic toolchain exclusively, it won't hurt.

### Use case: zig-cc for targets for multiple libc variants

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
This is a guardrail.

## Note: Naming

Both Go and Bazel naming schemes are accepted. For convenience with
Go, the following Go-style toolchain aliases are created:

|Bazel (zig) name | Go name  |
|---------------- | -------- |
|`x86_64`         | `amd64`  |
|`aarch64`        | `arm64`  |
|`wasm32`         | `wasm`   |
|`macos`          | `darwin` |
|`wasi`           | `wasip1` |

For example, the toolchain `linux_amd64_gnu.2.28` is aliased to
`x86_64-linux-gnu.2.28`. To find out which toolchains can be registered or
used, run:

```
$ bazel query @zig_sdk//toolchain/...
```

## Incompatibilities with clang and gcc

`zig cc` is *almost* a drop-in replacement for clang/gcc. This section lists
some of the discovered differences and ways to live with them.

### UBSAN and "SIGILL: Illegal Instruction"

`zig cc` differs from "mainstream" compilers by [enabling UBSAN by
default][ubsan1]. Which means your program may compile successfully and crash
with:

```
SIGILL: illegal instruction
```

This flag encourages program authors to fix the undefined behavior. There are
[many ways][ubsan2] to find the undefined behavior.

## Known Issues In `hermetic_cc_toolchain`

These are the things you may stumble into when using `hermetic_cc_toolchain`.
We are unlikely to implement them any time soon, but patches implementing those
will be accepted.

### Zig cache location

Currently zig cache is stored in `/var/tmp/zig-cache`, so `bazel clean
--expunge` will not clear the zig cache. Zig's cache should be stored somewhere
in the project's path. It is not clear how to do it.

See [#83][pr-83] for more context.

### OSX: sysroot

For non-trivial programs (and for all darwin/arm64 cgo programs) MacOS SDK may
be necessary. Read [Jakub's comment][sysroot] about it. Support for OSX sysroot
is currently not implemented, but patches implementing it will be accepted, as
long as the OSX sysroot must come through an `http_archive`.

In essence, OSX target support is not well tested with `hermetic_cc_toolchain`.
Also see [#10][pr-10].

### Bazel 6 or earlier

Add to `.bazelrc`:

```
build --incompatible_enable_cc_toolchain_resolution
```

## Host Environments

This repository is used on the following (host) platforms:

- `linux_amd64`, a.k.a. `x86_64`.
- `linux_arm64`, a.k.a. `AArch64`.
- `darwin_amd64`, the 64-bit post-PowerPC models.
- `darwin_arm64`, the M1.
- `windows_amd64`, a.k.a. `x64`.

The tests are running (CId) on linux-amd64.

### Transient docker environment

A standalone Docker environment to play with `hermetic_cc_toolchain`:

```
$ docker run -e CC=/usr/bin/false -ti --rm -v "$PWD:/x" -w /x debian:bookworm-slim
# apt update && apt install --no-install-recommends -y shellcheck ca-certificates python3 git
# git config --global --add safe.directory /x
# tools/bazel test //...
# ./ci/lint
# ./ci/release
# ./ci/zig-wrapper
```
## Communication

We maintain two channels for comms:
- Github issues and pull requests.
- Slack: `#zig` in bazelbuild.slack.com.

### Previous Commuications

Previous communications were done in a mailing list; the past archive can be
accessed like this:

    git checkout v2.0.0-rc2 mailing-list-archive.mbox
    mutt -R -f mailing-list-archive.mbox

## Maintainers

- [@FabianHahn](https://github.com/FabianHahn/)
- [@jvolkman](https://github.com/jvolkman)
- [@laurynaslubys](https://github.com/laurynaslubys)
- [@linzhp](https://github.com/linzhp)
- [@motiejus](https://github.com/motiejus)
- [@sywhang](https://github.com/sywhang)

Guidelines for maintainers[^2]:

* Communicate intent precisely.
* Edge cases matter.
* Favor reading code over writing code.
* Only one obvious way to do things.
* Runtime crashes are better than bugs.
* Compile errors are better than runtime crashes.
* Incremental improvements.
* Avoid local maximums.
* Reduce the amount one must remember.
* Focus on code rather than style.
* Resource allocation may fail; resource deallocation must succeed.
* Memory is a resource.
* Together we serve the users.

On a more practical note:

- Maintainers can merge others' pull requests following their best judgement.
  They may or may not ask for feedback from other maintainers. Follow the Zen
  of Zig.
- Currently releases are coordinated with Uber employees, because they can test
  the version-to-be-released their [big repository][go-monorepo]. If you use
  `hermetic_cc_toolchain` in production and, more importantly, have a
  heterogeneous environment (different languages, RBE, different platforms), we
  encourage you to make yourself known. That way we can work together to
  validate it before cutting the release.

[^1]: a [mathematical subset][subset]: both can be equal.
[^2]: Credit: `zig zen`

[ajbouh]: https://github.com/ajbouh/bazel-zig-cc/
[sysroot]: https://github.com/ziglang/zig/issues/10299#issuecomment-989153750
[ubsan1]: https://github.com/ziglang/zig/issues/4830#issuecomment-605491606
[ubsan2]: https://github.com/ziglang/zig/issues/5163
[transitions]: https://docs.bazel.build/versions/main/skylark/config.html#user-defined-transitions
[subset]: https://en.wikipedia.org/wiki/Subset
[universal-headers]: https://github.com/ziglang/universal-headers
[go-monorepo]: https://www.uber.com/blog/go-monorepo-bazel/
[pr-83]: https://github.com/uber/hermetic_cc_toolchain/issues/83
[pr-10]: https://github.com/uber/hermetic_cc_toolchain/issues/10
[examples]: https://github.com/uber/hermetic_cc_toolchain/tree/main/examples
