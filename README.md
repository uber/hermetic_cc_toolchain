[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain

This is a C/C++ toolchain that can (cross-)compile C/C++ programs. It contains
clang-12, musl, glibc (versions 2-2.33, selectable), all in a ~40MB package.
Read
[here](https://andrewkelley.me/post/zig-cc-powerful-drop-in-replacement-gcc-clang.html)
about zig-cc; the rest of the README will present how to use this toolchain
from Bazel.

# Usage

Add this to your `WORKSPACE`:

```
BAZEL_ZIG_CC_VERSION = "v0.3.2"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "f28327aaf5d66cb7ca42977af6284faf9b8306df8e152fcfc82ae33ad92c443b",
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

Read [#Known Issues](#known-issues) before using.

# Known Issues

## Parallel `zig c++` invocations may fail

**Severity: High**

**Task:** [ziglang/zig #9431 FileNotFound when compiling macos](https://github.com/ziglang/zig/issues/9431)

Background: there is a race when calling `zig c++`, which Bazel does a lot.
This may fail compilation. Yours truly only reproduced it on macos with a cold
cache. Based on that, a workaround in the toolchain exists, named
`speed_first_safety_later`. The possible values are `auto` (default), `yes`,
`no`.

## relocation error with glibc < 2.32

**Severity: High**

**Task:** [ziglang/zig relocation error: symbol pthread_sigmask version GLIBC_2.2.5 not defined in file libc.so.6 with link time reference #7667](https://github.com/ziglang/zig/issues/7667)

Background: one of our internal shared libraries (which we must build with glibc 2.19) does not load on an older system:

```
id: relocation error: /lib/x86_64-linux-gnu/libnss_uber.so.2: symbol pthread_sigmask, version GLIBC_2.2.5 not defined in file libc.so.6 with link time reference
```

Severity is high, because there is no known workaround: the shared library,
when built with this toolchain, will not work on our target system.

## newer zig fails darwin tests

**Severity: Low**

Task: [ziglang/zig #9485 glibc 2.27 or older: fcntl64 not found, but zig's glibc headers refer it](https://github.com/ziglang/zig/issues/9485)

Background: when glibc 2.27 or older is selected, it may miss `fcntl64`. A
workaround is applied for `x86_64`, but not for aarch64. The same workaround
may apply to aarch64, but the author didn't find a need to test it (yet).

## cgo for darwin (macos)

**Severity: Low**

**Task:** [rules/go #2894 Per-arch_target linker flags](https://github.com/bazelbuild/rules_go/issues/2894)

Background: until there is a better "global" way (i.e. the task is solved), all
`go_binary` targets destined for Darwin (macos) need an extra `gc_linkopts`
flag:

```
go_binary(
    <...>
    gc_linkopts = select({
        "@platforms//os:macos": ["-s", "-w", "-buildmode=pie"],
        "//conditions:default": [],
    }),
)
```

A workaround with [gazelle](https://github.com/bazelbuild/bazel-gazelle) `map_kind` directive is possible. This will override rules_go `go_binary` rule with `go_binary` which contains default `gc_linkopts` parameters. Add this line to your BUILD files (usually adding to root BUILD file will suffice) and run `gazelle` to automatically generate `load` statements.

```
# gazelle:map_kind go_binary go_binary @bazel-zig-cc//rules:go_binary_override.bzl
```


## incorrect glibc version autodetection

**Severity: Low**

**Task:** [ziglang/zig zig detects wrong libc version #6469](https://github.com/ziglang/zig/issues/6469)

Background: zig detects an incorrect glibc version when not specified.
Therefore, until the task is resolved, registering a GNU toolchain without a
version suffix (e.g. `linux_amd64_gnu`) is not recommended. We recommend
specifying the suffix to the oldest system that is mean to run the compiled
binaries. This is safe, because glibc is backwards-compatible. Alternatively,
use musl.

# Closed issues

- [ziglang/zig #9139 zig c++ hanging when compiling in parallel](https://github.com/ziglang/zig/issues/9139) (CLOSED, thanks andrewrk)
- [golang/go #46644 cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644) (CLOSED, thanks kubkon)
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050) (CLOSED, thanks kubkon)
- [ziglang/zig #7917 [meta] better c/c++ toolchain compatibility](https://github.com/ziglang/zig/issues/7917) (CLOSED, thanks andrewrk)
- [ziglang/zig #7915 ar-compatible command for zig cc](https://github.com/ziglang/zig/issues/7915) (CLOSED, thanks andrewrk)

# Testing

## linux cgo + glibc 2.19

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
$ bazel build --platforms @io_bazel_rules_go//go/toolchain:darwin_amd64_cgo //test:gognu
...
$ file bazel-bin/test/gognu_/gognu
bazel-bin/test/gognu_/gognu: Mach-O 64-bit x86_64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>
```

## Transient docker environment

```
$ docker run -e CC=/usr/bin/false -ti --rm -v $(pwd):/x -w /x debian:bullseye-slim
# apt update && apt install direnv git -y
# . .envrc
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

# Credits

Many thanks to Adam Bouhenguel and his
[bazel-zig-cc](https://github.com/ajbouh/bazel-zig-cc/), the parent of this
repository.
