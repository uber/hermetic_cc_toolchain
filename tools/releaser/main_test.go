// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
package main

import (
	"fmt"
	"testing"
)

func TestRegex(t *testing.T) {
	tests := []struct {
		tag  string
		good bool
	}{
		{good: true, tag: "v1.0.0"},
		{good: true, tag: "v99.99.99"},
		{good: true, tag: "v1.0.1-rc1"},
		{good: true, tag: "v1.0.99-rc99"},
		{good: false, tag: ""},
		{good: false, tag: "v1.0"},
		{good: false, tag: "1.0.0"},
		{good: false, tag: "1.0.99-rc99"},
	}

	for _, tt := range tests {
		t.Run(fmt.Sprintf("tag=%s good=%s", tt.tag, tt.good), func(t *testing.T) {
			matched := tagRegexp.MatchString(tt.tag)

			if tt.good && !matched {
				t.Errorf("expected %s to be a valid tag, but it was not", tt.tag)
			} else if !tt.good && matched {
				t.Errorf("expected %s to be an invalida tag, but it was", tt.tag)
			}
		})
	}
}
