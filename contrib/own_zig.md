How to test a different version of zig
--------------------------------------

Assume you want to test an unreleased version of zig. Here's how:

1. Clone zig-bootstrap:

      $ git clone https://github.com/ziglang/zig-bootstrap
      $ cd zig-bootstrap

2. Copy over zig/ from ~/zig:

      $ rm -fr zig
      $ git -C ~/zig archive --format=tar --prefix=zig/ master | tar -xv

3. Build it (assuming `x86_64-linux`):

      $ vim build  # edit ZIG_VERSION
      $ ./build -j$(nproc) x86_64-linux-musl baseline

4. Pack the release tarball:

      $ ~/code/bazel-zig-cc/makerel

This gives us a usable Zig SDK. Now:

- Send the .tar.xz it to your mirror.
- Point toolchain/defs.bzl to the new version.
- Run tests.

Links
-----

- [ziglang/release-cutter][1], a script that creates binaries for [ziglang.org/download][2].
- [ziglang/zig-bootstrap][3], a set of scripts that compile a static Zig.

[1]: https://github.com/ziglang/release-cutter/blob/master/script
[2]: https://ziglang.org/download
[3]: https://github.com/ziglang/zig-bootstrap
