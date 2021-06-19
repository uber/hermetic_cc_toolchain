[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain for Go

This is a prototype zig-cc toolchain that can cross-compile cgo programs to these os/archs:

- x86_64-linux-gnu.2.19
- x86_64-linux-musl
- aarch-linux-gnu.2.19
- aarch-linux-musl
- x86_64-macos-gnu
- aarch64-macos-gnu

Convenient way is still being researched (see [Known Issues](#known-issues)).

# Testing

## linux cgo + glibc 2.19

Glibc toolchain is suffixed with `-gnu`:

```
$ bazel run --platforms @zig_sdk//:x86_64-linux-gnu //test:gognu
$ file bazel-bin/test/gognu_/gognu
bazel-bin/test/gognu_/gognu: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.0.0, Go BuildID=redacted, with debug_info, not stripped
```

## linux cgo + musl

```
$ bazel build --platforms @zig_sdk//:x86_64-linux-musl //test:gomusl
...
$ file ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=redacted, with debug_info, not stripped
$ ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
hello, world
```

## macos cgo

```
$ bazel build --platforms @zig_sdk//:x86_64-macos-gnu //test:gognu
...
$ file bazel-bin/test/gognu_/gognu
bazel-bin/test/gognu_/gognu: Mach-O 64-bit x86_64 executable, flags:<NOUNDEFS|DYLDLINK|TWOLEVEL|PIE>
```

## Transient docker environment

```
$ docker run -ti --rm -v $(pwd):/x -w /x debian:buster-slim
# apt update && apt install curl -y && curl -L https://github.com/bazelbuild/bazelisk/releases/download/v1.9.0/bazelisk-linux-amd64 > /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
# export CC=/usr/bin/false
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

# Known Issues

- [ziglang/zig #9139 zig c++ hanging when compiling in parallel](https://github.com/ziglang/zig/issues/9139)
- [rules/go #2894 Per-arch_target linker flags](https://github.com/bazelbuild/rules_go/issues/2894)

Closed issues:

- [golang/go #46644: cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644) (CLOSED)
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050) (CLOSED)
- [ziglang/zig #7917 [meta] better c/c++ toolchain compatibility](https://github.com/ziglang/zig/issues/7917) (CLOSED)
- [ziglang/zig #7915 ar-compatible command for zig cc](https://github.com/ziglang/zig/issues/7915) (CLOSED)
