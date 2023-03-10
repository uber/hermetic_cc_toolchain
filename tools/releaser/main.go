// Copyright 2023 Uber Technologies, Inc.
// Licensed under the Apache License, Version 2.0

// releaser is a tool for managing part of the process to release a new version of bazel-zig-cc.
package main

import (
	"crypto/sha256"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strconv"
	"strings"

)

var (
	// Paths to be included to the release
	_paths = []string{
		"LICENSE",
		"NOTICE",
		"README.md",
		"toolchain/*",
	}

	// regexp for valid tags
	tagRegexp = regexp.MustCompile(`^v([0-9]+)\\.([0-9]+)(\\.([0-9]+))(-rc([0-9]+))?$`)

	errTag = errors.New("tag accepts the following formats: v1.0.0 v1.0.1-rc1")
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func log(msg string, format ...any) {
	fmt.Fprintf(flag.CommandLine.Output(), msg+"\n", format...)
}

func run() error {
	var (
		goVersion    string
		repoRoot     string
		skipUpgrades bool
		tag          string
	)

	flag.StringVar(&goVersion, "go_version", "", "go version for go.mod")
	flag.StringVar(&repoRoot, "repo_root", os.Getenv("BUILD_WORKSPACE_DIRECTORY"), "root directory of bazel-zig-cc repo")
	flag.StringVar(&tag, "tag", "", "tag for this release")
	flag.BoolVar(&skipUpgrades, "skip_upgrades", false, "skip upgrade checks (testing only)")

	flag.Usage = func() {
		fmt.Fprint(flag.CommandLine.Output(), `usage: bazel run //tools/releaser -- -go_version <version> -tag <tag>

This utility is intended to handle many of the steps to release a new version.

`)
		flag.PrintDefaults()
	}

	flag.Parse()

	if tag == "" {
		return fmt.Errorf("ERROR: tag is required")
	}

	if !tagRegexp.MatchString(tag) {
		return errTag
	}

	var goVersionArgs []string
	if goVersion != "" {
		versionParts := strings.Split(goVersion, ".")
		if len(versionParts) < 2 {
			flag.Usage()
			return errors.New("please provide a valid Go version")
		}
		if minorVersion, err := strconv.Atoi(versionParts[1]); err != nil {
			return fmt.Errorf("%q is not a valid Go version", goVersion)
		} else if minorVersion > 0 {
			versionParts[1] = strconv.Itoa(minorVersion - 1)
		}
		goVersionArgs = append(goVersionArgs, "-go", goVersion, "-compat", strings.Join(versionParts, "."))
	}

	// external dependency checks
	depChecks := [][]string{
		{"go", "get", "-t", "-u", "./..."},
		append([]string{"tools/mod-tidy"}, goVersionArgs...),
	}

	// commands that Must Not Fail
	cmds := [][]string{
		{"tools/bazel", "run", "//:gazelle"},
		{"git", "diff", "--stat", "--exit-code"},
		{"git", "tag", tag},
	}

	log("Cutting a release:")
	if skipUpgrades {
		log("SKIPPING: go update commands")
	} else {
		cmds = append(depChecks, cmds...)
	}

	for _, c := range cmds {
		cmd := exec.Command(c[0], c[1:]...)
		cmd.Dir = repoRoot
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf(
				"ERROR: running %s:%w\n%s",
				strings.Join(c, " "),
				err,
				out,
			)
		}
	}

	log("Creating archive bazel-zig-cc-%s.tar", tag)

	cmd := exec.Command(
		"git",
		append([]string{"archive", "--format=tar", tag}, _paths...)...,
	)
	cmd.Dir = repoRoot

	out, err := cmd.Output()
	if err != nil {
		var exitError *exec.ExitError
		errors.As(err, &exitError)
		return fmt.Errorf("ERROR: failed to create git archive: %w\n%s", err, exitError.Stderr)
	}

	log("Compressing bazel-zig-cc-%s.tar", tag)

	tgz := Gzip(out)

	fpath := path.Join(repoRoot, fmt.Sprintf("bazel-zig-cc-%s.tar.gz", tag))
	if err := os.WriteFile(fpath, tgz, 0o644); err != nil {
		return fmt.Errorf("ERROR: write %q: %w", fpath, err)
	}

	log("Wrote %s", fpath)

	shasum := sha256.Sum256(tgz)

	log("Release boilerplate:\n-----\n" + genBoilerplate(tag, fmt.Sprintf("%x", shasum)))

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

# Argument-free will pick reasonable defaults.
zig_toolchains()

# version, url_formats and host_platform_sha256 are can be set for those who
# wish to control their Zig SDK version and where it is downloaded from
zig_toolchains(
    version = "<...>",
    url_formats = [
        "https://example.org/zig/zig-{host_platform}-{version}.{_ext}",
    ],
    host_platform_sha256 = { ... },
)`, version, shasum)
}
