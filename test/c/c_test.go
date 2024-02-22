package c_test

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
	"github.com/stretchr/testify/assert"
	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

func TestYadda(t *testing.T) {
	want := os.Getenv("WANT")

	binary, err := runfiles.Rlocation(os.Getenv("BINARY"))
	if err != nil {
		t.Fatalf("unable to locate guest binary: %v", err)
	}
	var got []byte
	switch os.Getenv("EXECUTOR") {
	case "NATIVE":
		got, err = exec.Command(binary).CombinedOutput()
	case "WASI":
		got, err = runWasi(binary)
	default:
		err = fmt.Errorf("unknown executor: %q", os.Getenv("EXECUTOR"))
	}
	if err != nil {
		t.Fatalf("run %q: %v", binary, err)
	}

	assert.Regexp(t, string(want), string(got))
}

func runWasi(binary string) ([]byte, error) {
	ctx := context.Background()
	r := wazero.NewRuntime(ctx)
	defer r.Close(ctx)
	buf := &bytes.Buffer{}
	config := wazero.NewModuleConfig().WithStdout(buf).WithStderr(buf).WithArgs("wasi")
	wasi_snapshot_preview1.MustInstantiate(ctx, r)
	bin, err := os.ReadFile(binary)
	if err != nil {
		return nil, fmt.Errorf("unable to read guest binary: %v", err)
	}
	_, err = r.InstantiateWithConfig(ctx, bin, config)
	if err != nil {
		return nil, fmt.Errorf("unable to create instantiate module: %v", err)
	}
	return buf.Bytes(), nil
}
