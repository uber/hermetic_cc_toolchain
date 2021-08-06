[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain

This is an early stage zig-cc toolchain that can cross-compile cgo programs to these os/archs:

- amd64-linux-gnu.2.19
- amd64-linux-musl
- arm64-linux-gnu.2.28
- arm64-linux-musl
- amd64-macos
- arm64-macos

# Usage

Add this to your `WORKSPACE`:

```
BAZEL_ZIG_CC_VERSION = "0.2"

http_archive(
    name = "bazel-zig-cc",
    sha256 = "0af0493e2d4822a94803e8a83703d25e0f9d8fe6ec4daf3b0ed3ca4cd6076650",
    strip_prefix = "bazel-zig-cc-{}".format(BAZEL_ZIG_CC_VERSION),
    urls = ["https://git.sr.ht/~motiejus/bazel-zig-cc/archive/{}.tar.gz".format(BAZEL_ZIG_CC_VERSION)],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_register_toolchains = "register_toolchains")

zig_register_toolchains()
```

This will register the "default" toolchains. Look into `register_toolchains` on
which parameters it accepts.

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
    --extra_toolchains @zig_sdk//:x86_64-linux-musl_toolchain //test:hello
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
$ docker run -e CC=/usr/bin/false -ti --rm -v $(pwd):/x -w /x debian:buster-slim
# apt update && apt install wget git -y
# . .envrc
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

# Known Issues

- [ziglang/zig #9485 glibc 2.27 or older: fcntl64 not found, but zig's glibc headers refer it](https://github.com/ziglang/zig/issues/9485)
- [ziglang/zig #9431 FileNotFound when compiling macos](https://github.com/ziglang/zig/issues/9431)
- [rules/go #2894 Per-arch_target linker flags](https://github.com/bazelbuild/rules_go/issues/2894)

Closed issues:

- [ziglang/zig #9139 zig c++ hanging when compiling in parallel](https://github.com/ziglang/zig/issues/9139) (CLOSED)
- [golang/go #46644 cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644) (CLOSED)
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050) (CLOSED)
- [ziglang/zig #7917 [meta] better c/c++ toolchain compatibility](https://github.com/ziglang/zig/issues/7917) (CLOSED)
- [ziglang/zig #7915 ar-compatible command for zig cc](https://github.com/ziglang/zig/issues/7915) (CLOSED)
