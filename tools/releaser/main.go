// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

// releaser is a tool for managing part of the process to release a new version
// of hermetic_cc_toolchain.
package main

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strings"
	"time"

	bzl "github.com/bazelbuild/buildtools/build"
)

var (
	// regexp for valid tags
	_tagRegexp = regexp.MustCompile(`^v([0-9]+)\.([0-9]+)(\.([0-9]+))(-rc([0-9]+))?$`)

	_errTag = errors.New("tag accepts the following formats: v1.0.0 v1.0.1-rc1")

	// releaser is able to calculate the hash of any existing release. However,
	// if the releaser was changed since cutting the hash (e.g. files got added
	// or removed, the tar format changed, etc), then the previously-released
	// tarball will not match the hash. Since we cannot change the hash since
	// it was released, we can hardcode it here.
	//
	// Normally you don't need to set this value, unless the CI job updates the
	// hashes of already-released versions. Then just hardcode it here.
	_tagHashes = map[string]string{
		"v2.0.0-rc2": "40dff82816735e631e8bd51ede3af1c4ed1ad4646928ffb6a0e53e228e55738c",
		"v2.0.0": "57f03a6c29793e8add7bd64186fc8066d23b5ffd06fe9cc6b0b8c499914d3a65",
	}

	_boilerplateFiles = []string{
		"README.md",
		"examples/rules_cc/WORKSPACE",
	}
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
		repoRoot        string
		tag             string
		skipBranchCheck bool
	)

	flag.StringVar(&repoRoot, "repoRoot", os.Getenv("BUILD_WORKSPACE_DIRECTORY"), "root directory of hermetic_cc_toolchain repo")
	flag.StringVar(&tag, "tag", "", "tag for this release")
	flag.BoolVar(&skipBranchCheck, "skipBranchCheck", false, "skip branch check (for testing the release tool)")

	flag.Usage = func() {
		fmt.Fprint(flag.CommandLine.Output(), `usage: bazel run //tools/releaser -- -repoRoot <repoRoot> -tag <tag>

This utility is intended to handle many of the steps to release a new version.

`)
		flag.PrintDefaults()
	}

	flag.Parse()

	if tag == "" {
		return fmt.Errorf("tag is required")
	}

	if !_tagRegexp.MatchString(tag) {
		return _errTag
	}

	type checkType struct {
		args    []string
		wantOut string
	}

	checks := []checkType{{[]string{"diff", "--stat", "--exit-code"}, ""}}
	if !skipBranchCheck {
		checks = append(
			checks,
			checkType{[]string{"branch", "--show-current"}, "main\n"},
		)
	}

	log("checking if git tree is ready for the release")
	for _, c := range checks {
		out, err := git(repoRoot, c.args...)
		if err != nil {
			return err
		}

		if string(out) == c.wantOut {
			continue
		}

		return fmt.Errorf(
			"unexpected output for %q. Expected %q, got:\n---\n%s\n---\n",
			"git "+strings.Join(c.args, " "),
			c.wantOut,
			out,
		)
	}


	if err := checkZigMirrored(repoRoot); err != nil {
		return fmt.Errorf("zig is correctly mirrored: %w", err)
	}

	// if the tag already exists, do not cut a new one.
	tagAlreadyExists := false
	// cut a new tag if the tag does not already exist.
	if out, err := git(repoRoot, "tag", "-l", tag); err != nil {
		return err
	} else {
		tagAlreadyExists = strings.TrimSpace(out) == tag
	}

	if hash, ok := _tagHashes[tag]; ok {
		log("Asked for a pre-existing release which has a hardcoded hash. " +
			"Running in 'check-only' mode.")
		boilerplate := genBoilerplate(tag, hash)
		if err := updateBoilerplate(repoRoot, boilerplate, tag); err != nil {
			return fmt.Errorf("update boilerplate: %w", err)
		}
		log("updated %s", strings.Join(_boilerplateFiles, " and "))
		sep := strings.Repeat("-", 72)
		log("Release boilerplate:\n%[1]s\n%[2]s%[1]s\n", sep, boilerplate)
		return nil
	}

	releaseRef := "HEAD"
	if tagAlreadyExists {
		releaseRef = tag
	}

	hash1, err := makeTgz(io.Discard, repoRoot, releaseRef)
	if err != nil {
		return fmt.Errorf("calculate hash1 of release tarball: %w", err)
	}

	boilerplate := genBoilerplate(tag, hash1)
	if err := updateBoilerplate(repoRoot, boilerplate, tag); err != nil {
		return fmt.Errorf("update boilerplate: %w", err)
	}

	// If tag does not exist, create a new commit with the updated hashes
	// and cut the new tag.
	//
	// If the tag exists, skip committing the tag; we will just verify
	// that the hashes in the README and examples/ are up to date.
	if !tagAlreadyExists {
		commitMsg := fmt.Sprintf("Releasing hermetic_cc_toolchain %s", tag)
		if _, err := git(repoRoot, "commit", "-am", commitMsg); err != nil {
			return err
		}
		if _, err := git(repoRoot, "tag", tag); err != nil {
			return err
		}
	}

	// Cut the final release and compare hash1 and hash2 just in case.
	fpath := path.Join(repoRoot, fmt.Sprintf("hermetic_cc_toolchain-%s.tar.gz", tag))
	tgz, err := os.Create(fpath)
	if err != nil {
		return err
	}
	defer func() {
		if _err != nil {
			os.Remove(fpath)
		}
	}()

	hash2, err := makeTgz(tgz, repoRoot, tag)
	if err != nil {
		return fmt.Errorf("make release tarball: %w")
	}

	if err := tgz.Close(); err != nil {
		return err
	}

	if hash1 != hash2 {
		// This may happen if the release tarball depends on the boilerplate
		// that gets updated with the new tag. Don't do this. We want the
		// release commit to point to the correct hashes for that release.
		return fmt.Errorf(
			"hashes before and after release differ: %s %s",
			hash1,
			hash2,
		)
	}

	log("wrote %s, sha256: %s", fpath, hash2)

	sep := strings.Repeat("-", 72)
	log("Release boilerplate:\n%[1]s\n%[2]s%[1]s\n", sep, boilerplate)

	return nil
}

func genBoilerplate(version, shasum string) string {
	return fmt.Sprintf(`load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

HERMETIC_CC_TOOLCHAIN_VERSION = "%[1]s"

http_archive(
    name = "hermetic_cc_toolchain",
    sha256 = "%[2]s",
    urls = [
        "https://mirror.bazel.build/github.com/uber/hermetic_cc_toolchain/releases/download/{0}/hermetic_cc_toolchain-{0}.tar.gz".format(HERMETIC_CC_TOOLCHAIN_VERSION),
        "https://github.com/uber/hermetic_cc_toolchain/releases/download/{0}/hermetic_cc_toolchain-{0}.tar.gz".format(HERMETIC_CC_TOOLCHAIN_VERSION),
    ],
)

load("@hermetic_cc_toolchain//toolchain:defs.bzl", zig_toolchains = "toolchains")

# Plain zig_toolchains() will pick reasonable defaults. See
# toolchain/defs.bzl:toolchains on how to change the Zig SDK version and
# download URL.
zig_toolchains()
`, version, shasum)
}

// updateBoilerplate updates all example files with the given version.
func updateBoilerplate(repoRoot string, boilerplate string, tag string) error {
	const (
		startMarker = `load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")` + "\n"
		endMarker   = "zig_toolchains()\n"
	)

	for _, gotpath := range _boilerplateFiles {
		f := path.Join(repoRoot, gotpath)
		data, err := os.ReadFile(f)
		if err != nil {
			return err
		}
		dataStr := string(data)

		// all boilerplate starts with startMarker and ends with endMarker.
		// Our goal is to write the right string between the two.
		startMarkerIdx := strings.Index(dataStr, startMarker)
		if startMarkerIdx == -1 {
			return fmt.Errorf("%q does not contain start marker %q...", gotpath, startMarker[0:16])
		}

		endMarkerIdx := strings.Index(dataStr, endMarker)
		if endMarkerIdx == -1 {
			return fmt.Errorf("%q does not contain end marker %q...", gotpath, endMarker[0:16])
		}

		preamble := dataStr[0:startMarkerIdx]
		epilogue := dataStr[endMarkerIdx+len(endMarker):]
		newBoilerplate := preamble + boilerplate + epilogue

		if err := os.WriteFile(f, []byte(newBoilerplate), 0644); err != nil {
			return fmt.Errorf("write %q: %w", err)
		}
	}

	return updateBzlmod(repoRoot, tag)
}

func updateBzlmod(repoRoot string, tag string) error {
	boilerplate := fmt.Sprintf(`
module(
    name = "hermetic_cc_toolchain",
    version = "%s",
)
`, tag)

	const marker = "\nbazel_dep(name = \"rules_go\""

	bzlmodPath := path.Join(repoRoot, "MODULE.bazel")
	data, err := os.ReadFile(bzlmodPath)
	if err != nil {
		return err
	}
	dataStr := string(data)

	markerIdx := strings.Index(dataStr, marker)
	if markerIdx == -1 {
		return fmt.Errorf("%q does not contain marker %q", bzlmodPath, marker)
	}

	epilogue := dataStr[markerIdx:]

	if err := os.WriteFile(bzlmodPath, []byte(boilerplate + epilogue), 0644); err != nil {
		return fmt.Errorf("write %q: %w", err)
	}
	return nil
}

func git(repoRoot string, args ...string) (string, error) {
	cmd := exec.Command("git", args...)
	cmd.Dir = repoRoot
	out, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf(
			"git %s: %v\n---\n%s\n---\n",
			strings.Join(args, " "),
			err,
			out,
		)
	}
	return string(out), nil
}

func makeTgz(w io.Writer, repoRoot string, ref string) (string, error) {
	hashw := sha256.New()

	gzw, err := gzip.NewWriterLevel(io.MultiWriter(w, hashw), gzip.BestCompression)
	if err != nil {
		return "", fmt.Errorf("create gzip writer: %w", err)
	}

	tw := tar.NewWriter(gzw)

	// WORKSPACE in the resulting tarball needs to be much
	// smaller than of hermetic_cc_toolchain. See #15.
	// See that README why we are not adding the top-level README.md.
	// These files will become top-level during processing.
	substitutes := map[string]string{
		"tools/releaser/data/WORKSPACE": "WORKSPACE",
		"tools/releaser/data/README":    "README",
	}

	removals := map[string]struct{}{
		"tools/": struct{}{},
		"tools/releaser/": struct{}{},
		"tools/releaser/data/": struct{}{},
	}

	// Paths to be included to the release
	cmd := exec.Command(
		"git",
		"archive",
		"--format=tar",
		ref,
		"LICENSE",
		"MODULE.bazel",
		"toolchain/*",

		// files to be renamed
		"tools/releaser/data/WORKSPACE",
		"tools/releaser/data/README",
	)

	// the tarball produced by `git archive` has too many artifacts:
	// - file metadata is different when different SHAs are used.
	// - the archive contains the repo SHA as a "comment".
	// Therefore, parse whatever `git archive` outputs and sanitize it.
	cmd.Dir = repoRoot
	cmd.Stderr = os.Stderr

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", fmt.Errorf("StdoutPipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return "", fmt.Errorf("git archive: %w", err)
	}

	tr := tar.NewReader(stdout)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("read archive: %w", err)
		}

		// pax headers contain things we want to clean in
		// the first place.
		if hdr.Typeflag == tar.TypeXGlobalHeader {
			continue
		}

		name := hdr.Name

		if _, ok := removals[name]; ok {
			continue
		}

		if n, ok := substitutes[name]; ok {
			name = n
		}

		if err := tw.WriteHeader(&tar.Header{
			Name:    name,
			Mode:    int64(hdr.Mode & 0777),
			Size:    hdr.Size,
			ModTime: time.Date(2000, time.January, 1, 0, 0, 0, 0, time.UTC),
			Format:  tar.FormatGNU,
		}); err != nil {
			return "", err
		}

		if _, err := io.Copy(tw, tr); err != nil {
			return "", err
		}

	}

	if err := tw.Close(); err != nil {
		return "", fmt.Errorf("close tar writer: %w", err)
	}

	if err := gzw.Close(); err != nil {
		return "", fmt.Errorf("close gzip stream: %w", err)
	}

	if err := cmd.Wait(); err != nil {
		return "", fmt.Errorf("wait: %w", err)
	}

	return fmt.Sprintf("%x", hashw.Sum(nil)), nil
}

type zigUpstream struct {
	version     string // e.g. 0.11.0-dev.2619+bd3e248c7
	urlTemplate string // https://mirror.bazel.build/ziglang.org/builds/zig-{host_platform}-{version}.{_ext}
}

// check if zig sdk is properly mirrored
func checkZigMirrored(repoRoot string) error {
	upstream, err := parseZigUpstream(path.Join(repoRoot, "toolchain", "defs.bzl"))
	if err != nil {
		return err
	}

	// spot-checking only windows-x86_64, because:
	// - to check all platforms, we should parse much more of defs.bzl.
	// - so we'd rather pick a single platform and test it.
	// - because windows coverage is smallest, let's take the windows platform.
	url := strings.Replace(upstream.urlTemplate, "{host_platform}", "windows-x86_64", 1)
	url = strings.Replace(url, "{version}", upstream.version, 1)
	url = strings.Replace(url, "{_ext}", "zip", 1)

	log("checking if zig is mirorred in %q", url)

	resp, err := http.Head(url)
	if err != nil {
		return err
	}

	if resp.StatusCode != 200 {
		return fmt.Errorf("got non-200: %s", resp.Status)
	}

	return nil
}

// parseZigUpstrem parses "_VERSION" from toolchain/defs.bzl
func parseZigUpstream(defsPath string) (zigUpstream, error) {
	ret := zigUpstream{}

	data, err := os.ReadFile(defsPath)
	if err != nil {
		return zigUpstream{}, err
	}
	parsed, err := bzl.Parse(defsPath, data)
	if err != nil {
		return zigUpstream{}, err
	}

	for _, expr := range parsed.Stmt {
		def, ok := expr.(*bzl.AssignExpr)
		if !ok {
			continue
		}

		key := def.LHS.(*bzl.Ident)
		var to *string

		switch key.Name {
		case "_VERSION":
			to = &ret.version
		case "URL_FORMAT_BAZELMIRROR":
			to = &ret.urlTemplate
		default:
			continue
		}

		value, ok := def.RHS.(*bzl.StringExpr)
		if !ok {
			return zigUpstream{}, errors.New("got a non-string expression")
		}

		*to = value.Value
	}

	if ret.version == "" || ret.urlTemplate == "" {
		return zigUpstream{}, errors.New("_VERSION and/or URL_FORMAT_BAZELMIRROR not found")
	}

	return ret, nil
}
