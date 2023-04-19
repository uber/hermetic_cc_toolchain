// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

// releaser is a tool for managing part of the process to release a new version of bazel-zig-cc.
package main

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strings"
)

var (
	// Paths to be included to the release
	_paths = []string{
		"LICENSE",
		"README.md",
		"toolchain/*",
	}

	// regexp for valid tags
	tagRegexp = regexp.MustCompile(`^v([0-9]+)\.([0-9]+)(\.([0-9]+))(-rc([0-9]+))?$`)

	errTag = errors.New("tag accepts the following formats: v1.0.0 v1.0.1-rc1")
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %s\n", err)
		os.Exit(1)
	}
}

func log(msg string, format ...any) {
	fmt.Fprintf(flag.CommandLine.Output(), msg+"\n", format...)
}

func run() (_err error) {
	var (
		repoRoot string
		tag      string
	)

	flag.StringVar(&repoRoot, "repo_root", os.Getenv("BUILD_WORKSPACE_DIRECTORY"), "root directory of bazel-zig-cc repo")
	flag.StringVar(&tag, "tag", "", "tag for this release")

	flag.Usage = func() {
		fmt.Fprint(flag.CommandLine.Output(), `usage: bazel run //tools/releaser -- -go_version <version> -tag <tag>

This utility is intended to handle many of the steps to release a new version.

`)
		flag.PrintDefaults()
	}

	flag.Parse()

	if tag == "" {
		return fmt.Errorf("tag is required")
	}

	if !tagRegexp.MatchString(tag) {
		return errTag
	}

	// commands that Must Not Fail
	cmds := [][]string{
		{"git", "diff", "--stat", "--exit-code"},
		{"git", "tag", tag},
	}

	log("Cutting a release:")

	for _, c := range cmds {
		cmd := exec.Command(c[0], c[1:]...)
		cmd.Dir = repoRoot
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf(
				"run %s: %w\n%s",
				strings.Join(c, " "),
				err,
				out,
			)
		}
	}

	fpath := path.Join(repoRoot, fmt.Sprintf("bazel-zig-cc-%s.tar.gz", tag))
	tgz, err := os.Create(fpath)
	if err != nil {
		return err
	}
	defer func() {
		if _err != nil {
			os.Remove(fpath)
		}
	}()
	hashw := sha256.New()

	gzw, err := gzip.NewWriterLevel(io.MultiWriter(tgz, hashw), gzip.BestCompression)
	if err != nil {
		return fmt.Errorf("create gzip writer: %w", err)
	}

	log("- creating %s", fpath)

	var stderr bytes.Buffer
	cmd := exec.Command(
		"git",
		append([]string{
			"archive",
			"--format=tar",
			// WORKSPACE in the resulting tarball needs to be much
			// smaller than of bazel-zig-cc. See #15.
			"--add-file=tools/releaser/WORKSPACE",
			tag,
		}, _paths...)...,
	)
	cmd.Dir = repoRoot
	cmd.Stdout = gzw
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		var exitError *exec.ExitError
		errors.As(err, &exitError)
		return fmt.Errorf("create git archive: %w\n%s", err, stderr.Bytes())
	}

	if err := gzw.Close(); err != nil {
		return fmt.Errorf("close gzip stream: %w", err)
	}

	if err := tgz.Close(); err != nil {
		return err
	}
	log("- wrote %s", fpath)
	log("Release:\n-----\n" + genBoilerplate(tag, fmt.Sprintf("%x", hashw.Sum(nil))))

	return nil
}

func genBoilerplate(version, shasum string) string {
	return fmt.Sprintf(`load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

http_archive(
    name = "bazel-zig-cc",
    sha256 = "%[2]s",
    urls = [
        "https://mirror.bazel.build/github.com/uber/bazel-zig-cc/releases/download/%[1]s/bazel-zig-cc-%[1]s.tar.gz",
        "https://github.com/uber/bazel-zig-cc/releases/download/%[1]s/bazel-zig-cc-%[1]s.tar.gz",
    ],
)

load("@bazel-zig-cc//toolchain:defs.bzl", zig_toolchains = "toolchains")

# plain zig_toolchains() will pick reasonable defaults. See
# toolchain/defs.bzl:toolchains on how to change the Zig SDK path and version.
zig_toolchains()`, version, shasum)
}
