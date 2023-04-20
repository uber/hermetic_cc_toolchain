// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

package main

import (
	"testing"
)

func TestHello(t *testing.T) {
	want := "hello, world"
	got := Chello()
	if got != want {
		t.Errorf("expected %q, got %q", want, got)
	}
}
