#!/usr/bin/env bash
# Invocable skill entrypoint, independent of the current working directory.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
exec bash "$repo_dir/tools/configure.sh" "$@"
