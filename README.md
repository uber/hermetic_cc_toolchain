[![builds.sr.ht status](https://builds.sr.ht/~motiejus/bazel-zig-cc.svg)](https://builds.sr.ht/~motiejus/bazel-zig-cc)

# Bazel zig cc toolchain for Go

This is a prototype zig-cc toolchain that can compile cgo programs with these c
libraries:

- glibc 2.19
- musl

glibc 2.19 is the default. That means, glibc 2.19 toolchain is registered with
these basic constraints:

```
[
    "@platforms//os:linux",
    "@platforms//cpu:x86_64",
]
```

# Testing

## linux cgo + glibc 2.19

Using the default toolchain:

```
$ bazel build --toolchain_resolution_debug=true //test:gognu
...
$ ../bazel-bin/test/gognu_/gognu
hello, world
$ file ../bazel-bin/test/gognu_/gognu
../bazel-bin/test/gognu_/gognu: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.0.0, Go BuildID=redacted, with debug_info, not stripped
```

Explicitly the toolchain explicitly `-gnu`:
```
$ bazel run --platforms @com_github_ziglang_zig//:platform_x86_64-linux-gnu //test:gognu
```

## linux cgo + musl

```
$ bazel build --platforms @com_github_ziglang_zig//:platform_x86_64-linux-musl //test:gomusl
...
$ file ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=redacted, with debug_info, not stripped
$ ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
hello, world
```

## macos cgo + gnu

Does not work?

```
$ bazel build --platforms @com_github_ziglang_zig//:platform_x86_64-macos-musl //test:gognu
...
```

## Transient docker environment

```
$ docker run -ti --rm -v $(pwd):/x -w /x debian:buster-slim
# apt update && apt install curl -y && curl -L https://github.com/bazelbuild/bazelisk/releases/download/v1.9.0/bazelisk-linux-amd64 > /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
# export CC=/usr/bin/false
```

And run the `bazel build` commands above. Take a look at `.build.yml` and see
how CI does it.

# Appendix: compiling manually

zcc
```
#!/bin/bash
exec zig cc -target x86_64-macos-gnu "$@"
```

Build:
```
GOOS=darwin GOARCH=amd64 CC=zcc go build -ldflags "-linkmode external -extldflags -static" hello.go
```

# Known Issues

- <del>[golang/go #46644: cmd/link: with CC=zig: SIGSERV when cross-compiling to darwin/amd64](https://github.com/golang/go/issues/46644)</del>
- [ziglang/zig #9050 golang linker segfault](https://github.com/ziglang/zig/issues/9050)
