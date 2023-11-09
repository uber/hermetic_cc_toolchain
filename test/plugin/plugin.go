// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
//
// Package main tests that Zig can compile a Go plugin.
//
// As of writing, this fails:
//
//	$ CGO_ENABLED=1 CC="zig cc" GOOS=linux GOARCH=arm64 go build -linkmode=plugin .
//	link: ARM64 external linker must be gold (issue #15696, 22040), but is not: zig ld 0.11.0
//
// More context: https://github.com/uber/hermetic_cc_toolchain/issues/122
//
// This fails, because Go toolchain ask the string "GNU gold" in the output of
// `$CC -fuse-ld=gold -Wl,--version` when linking the Go plugin.
// See: https://go.googlesource.com/go/+/8c92897e15d15fbc664cd5a05132ce800cf4017f/src/cmd/link/internal/ld/lib.go#1628
package main
