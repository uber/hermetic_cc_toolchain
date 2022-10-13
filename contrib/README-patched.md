Patched Zig release
-------------------

This file explains how this zig version was created. As of first writing,
0.10.0-dev.4301+uber1 + https://github.com/ziglang/zig-bootstrap/pull/131

Steps to re-create a patched zig:

```
$ wget https://github.com/ziglang/zig/pull/13051.patch
$ git clone https://github.com/ziglang/zig-bootstrap; cd zig-bootstrap

# if https://github.com/ziglang/zig-bootstrap/pull/131 is not merged: patch it.

$ git am --directory=zig ../13051.patch

$ ${EDITOR:-vi} build  # replace the hash with "+uber1" and bump the last number in ZIG_VERSION

$ ./build-and-archive
```

Recent zig-bootstrap versions require cmake >= 3.19, which is available from
ubuntu 22.04 (jammy) or debian 12 (bookworm). Otherwise CMAKE will unable to
"Find the C compiler". A workaround:

    docker run --privileged -v `pwd`:/x -w /x -ti --rm buildpack-deps:bookworm \
        sh -c 'apt-get update && apt-get install -y cmake && exec ./build-and-archive'

(`--privileged` is necessary because of devpod nuances. You can skip it if you
don't know what is a devpod.)

`build-and-archive`, this file and 13051.patch should be in the archive where
you got your patched zig.
