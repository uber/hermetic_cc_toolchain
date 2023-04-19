#!/bin/sh

# Copyright 2023 Uber Technologies, Inc.
# Licensed under the MIT License

set -eu

# shellcheck disable=SC2153
want=$WANT
# shellcheck disable=SC2153
binary=$BINARY
got=$($binary)

if [ "$got" != "$want" ]; then
    echo wanted:
    echo \ \ "$want"
    echo got:
    echo \ \ "$got"
    exit 1
fi
