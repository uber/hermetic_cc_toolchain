# Copyright 2023 Uber Technologies, Inc.
# Licensed under the Apache License, Version 2.0

if [ -z "${BUILDKITE_BUILD_NUMBER:-}" ]; then
    >&2 echo "error: expected to run in buildkite"
    exit 1
fi

export BAZEL_ZIG_CC_CACHE_PREFIX="/tmp/bazel-zig-cc${BUILDKITE_BUILD_NUMBER}"
mkdir -p "$BAZEL_ZIG_CC_CACHE_PREFIX"

cat > .custom.ci.bazelrc <<EOF
common --repo_env BAZEL_ZIG_CC_CACHE_PREFIX="$BAZEL_ZIG_CC_CACHE_PREFIX"
build --sandbox_writable_path "$BAZEL_ZIG_CC_CACHE_PREFIX"
EOF
