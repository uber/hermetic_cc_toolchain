// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
//
// Package main tests that Zig can compile race-enabled tests.
//
// As of writing, this fails:
//   CGO_ENABLED=1 CC="zig cc" go test -race .
//
// More context: https://github.com/ziglang/zig/issues/11398
//
// This fails, because `zig cc` adds `--gc-sections` to the linker
// flag by default, which is incompatible with cgo. bazel-zig-cc
// adds a workaround for it.
package main

func main() {}
