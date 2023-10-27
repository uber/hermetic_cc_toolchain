// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

package main

import (
	"debug/elf"
	"os"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
)

func TestBuild(t *testing.T) {
	expectedMachineString := os.Getenv("PLUGIN_ELF_MACH")
	if expectedMachineString == "" {
		t.Fatalf("Env variable PLUGIN_ELF_MACH not defined")
	}

	pluginBinaryRPath := os.Getenv("PLUGIN_BINARY")

	pluginBinaryPath, err := runfiles.Rlocation(pluginBinaryRPath)
	if err != nil {
		t.Fatalf("can't find runfile %q: %v", pluginBinaryRPath, err)
	}

	bin, err := elf.Open(pluginBinaryPath)
	if err != nil {
		t.Fatalf("can't open file %q: %v", pluginBinaryPath, err)
	}

	t.Cleanup(func() {
		if err := bin.Close(); err != nil {
			t.Errorf("can't close ELF file: %v", err)
		}
	})

	if bin.Type != elf.ET_DYN {
		t.Errorf("ELF type %q incorrect, %q expected", bin.Type, elf.ET_DYN)
	}

	expectedMachine, _ := map[string]elf.Machine{
		"x86_64":  elf.EM_X86_64,
		"aarch64": elf.EM_AARCH64,
	}[expectedMachineString]

	if bin.Machine != expectedMachine {
		t.Errorf("ELF machine %q incorrect, %q expected", bin.Machine, expectedMachine)
	}

	var hasDynamicSection bool
	for _, s := range bin.Sections {
		if s.Type == elf.SHT_DYNAMIC {
			hasDynamicSection = true
			break
		}
	}

	if !hasDynamicSection {
		t.Error("No dynamic section found in the ELF binary")
	}
}
