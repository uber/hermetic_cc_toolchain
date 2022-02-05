How to test a different version of zig
--------------------------------------

Assume you want to test an unreleased version of zig. Here's how:

- build zig in `build/` directory, following the official instructions.
- pack it to something that looks like a release using this script:

```bash
#!/bin/bash
set -xeuo pipefail

archversion="zig-linux-x86_64-$(git describe)"
dst="$HOME/rel/$archversion/"
rm -fr "$dst"
mkdir -p "$dst"/docs
cp zig "$dst"
cp -r ../lib "$dst"
tar -C "$HOME/rel" -cJf "$HOME/$archversion.tar.xz" .
```

- send it to jakstys.lt or your mirror.
- point toolchain/defs.bzl to the new version.
- run tests (probably locally, where zig was built).
- running this on sr.ht is left as an exercise for further tests.
