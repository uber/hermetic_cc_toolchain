#/bin/bash

set -euo pipefail

want=$WANT
binary=$BINARY

got=$($binary)

if [[ "$got" != "$want" ]]; then
    echo wanted:
    echo \ \ "$want"
    echo got:
    echo \ \ "$got"
    exit 1
fi
