package c_test

import (
	"os"
	"os/exec"
	"testing"

	"github.com/bazelbuild/rules_go/go/runfiles"
	"github.com/stretchr/testify/assert"
)

func TestYadda(t *testing.T) {
	want := os.Getenv("WANT")

	binary, err := runfiles.Rlocation(os.Getenv("BINARY"))
	if err != nil {
		t.Fatalf("unable to locate guest binary: %v", err)
	}

	got, err := exec.Command(binary).CombinedOutput()
	if err != nil {
		t.Fatalf("run %q: %v", binary, err)
	}

	assert.Regexp(t, string(want), string(got))
}
