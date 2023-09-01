// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License
package main

import (
	"fmt"
	"os"
	"path"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
			matched := _tagRegexp.MatchString(tt.tag)

			if tt.good && !matched {
				t.Errorf("expected %s to be a valid tag, but it was not", tt.tag)
			} else if !tt.good && matched {
				t.Errorf("expected %s to be an invalida tag, but it was", tt.tag)
			}
		})
	}
}

func TestParseZigVersion(t *testing.T) {
	tests := []struct {
		name     string
		contents string
		want     zigUpstream
		wantErr  string
	}{
		{
			name:     "released url",
			contents: `_VERSION = "0.11.0"; URL_FORMAT_RELEASE = "https://ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}"`,
			want: zigUpstream{
				version:     "0.11.0",
				urlTemplate: "https://mirror.bazel.build/ziglang.org/download/{version}/zig-{host_platform}-{version}.{_ext}",
			},
		},
		{
			name:     "nightly url",
			contents: `_VERSION = "0.11.0-dev.2619+bd3e248c7"; URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"`,
			want: zigUpstream{
				version:     "0.11.0-dev.2619+bd3e248c7",
				urlTemplate: "https://mirror.bazel.build/ziglang.org/builds/zig-{host_platform}-{version}.{_ext}",
			},
		},
		{
			name:     "not an assignment",
			contents: `def _VERSION(x): return x`,
			wantErr:  "got a non-string expression",
		},
		{
			name:     "missing version assignment",
			contents: "x1 = 1",
			wantErr:  "assign statement _VERSION = <...> not found",
		},
		{
			name:     "missing url assignment",
			contents: `_VERSION = "0.11.0"; URL_FORMAT_NIGHTLY = "https://ziglang.org/builds/zig-{host_platform}-{version}.{_ext}"`,
			wantErr:  "url format for '0.11.0' not found",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			dir := t.TempDir()
			fname := path.Join(dir, "toolchain.defs")
			require.NoError(t, os.WriteFile(fname, []byte(tt.contents), 0644))

			got, err := parseZigUpstream(fname)
			if tt.wantErr != "" {
				assert.Error(t, err, tt.wantErr)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}
