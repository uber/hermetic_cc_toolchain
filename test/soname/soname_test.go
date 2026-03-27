// Copyright 2025 Uber Technologies, Inc.
// Licensed under the MIT License

// Tests that the zig cc toolchain embeds a SONAME (DT_SONAME) in shared
// libraries. Without the soname feature in zig_cc_toolchain.bzl, DT_SONAME
// is absent: the linker records the full build-time path in DT_NEEDED of
// any binary that links against the library, breaking runtime loading.
package soname_test

import (
	"debug/elf"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func TestSONAMEPresent(t *testing.T) {
	lib, err := runfiles.Rlocation(os.Getenv("LIB"))
	if err != nil {
		t.Fatalf("locate shared library: %v", err)
	}

	f, err := elf.Open(lib)
	if err != nil {
		t.Fatalf("open ELF: %v", err)
	}
	defer f.Close()

	sonames, err := f.DynString(elf.DT_SONAME)
	if err != nil {
		t.Fatalf("read DT_SONAME: %v", err)
	}

	if len(sonames) == 0 {
		t.Fatal("DT_SONAME is missing from shared library; " +
			"the soname feature in zig_cc_toolchain.bzl may not be applied")
	}

	const want = "libadd.so" // set by Bazel from the cc_binary output name
	if sonames[0] != want {
		t.Errorf("DT_SONAME = %q, want %q", sonames[0], want)
	}
}
