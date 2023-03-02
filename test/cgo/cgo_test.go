// Copyright 2023 Uber Technologies, Inc.
// Licensed under the Apache License, Version 2.0

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
