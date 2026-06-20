#!/usr/bin/env bash
# Source before `claude` to keep gstack state in this repo.
#   source scripts/gstack-env.sh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GSTACK_HOME="$ROOT/.gstack"
export GSTACK_STATE_ROOT="$GSTACK_HOME"
echo "GSTACK_HOME=$GSTACK_HOME"
