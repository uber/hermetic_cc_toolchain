# Bazel zig cc toolchain for Go

This is a prototype zig-cc toolchain for cgo programs with:

- glibc 2.19
- musl.

# Testing

## cgo + glibc 2.19

```
$ bazel build //test:gognu
...
$ ../bazel-bin/test/gognu_/gognu
hello, world
$ file ../bazel-bin/test/gognu_/gognu
../bazel-bin/test/gognu_/gognu: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.0.0, Go BuildID=redacted, with debug_info, not stripped
```

## cgo + musl

```
$ bazel build --platforms @com_github_ziglang_zig//:platform_linux-x86_64-musl :gomusl
...
$ file ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, Go BuildID=redacted, with debug_info, not stripped
$ ../bazel-out/k8-fastbuild-ST-d17813c235ce/bin/test/gomusl_/gomusl
hello, world
```

## Transient docker environment

```
$ docker run -ti --rm -v $(pwd):/x -w /x debian:buster-slim
# apt update && apt install curl ca-certificates -y && curl -L https://github.com/bazelbuild/bazelisk/releases/download/v1.7.5/bazelisk-linux-amd64 > /usr/local/bin/bazel && chmod +x /usr/local/bin/bazel
# export CC=/usr/bin/false
# bazel run --platforms @com_github_ziglang_zig//:platform_linux-x86_64-musl //test:gomusl
# bazel run --platforms @com_github_ziglang_zig//:platform_linux-x86_64-glibc //test:gognu
```
