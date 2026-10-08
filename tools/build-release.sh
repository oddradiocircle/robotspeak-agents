#!/usr/bin/env bash
# Builds the installable release assets from the committed tree into one folder:
# the full runtime, the Claude Desktop bundle, release notes and SHA-256 sums.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:?Usage: build-release.sh <output folder>}"
bash "$repo_dir/tests/versions.sh" >/dev/null
version="$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{version}' "$repo_dir/.claude-plugin/plugin.json")"
[[ -z "$(git -C "$repo_dir" status --porcelain)" ]] || { echo 'Commit every change before building a release' >&2; exit 1; }
mkdir -p "$out"
out="$(cd -- "$out" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Runtime for opencode, Hermes and manual installs: the committed tree as is.
git -C "$repo_dir" archive --format=tar.gz --prefix="robotspeak-agents-$version/" \
    -o "$out/robotspeak-agents-$version.tar.gz" HEAD
# Claude Desktop and Cowork: the MCP server with only what it runs.
git -C "$repo_dir" archive HEAD adapters/claude-desktop core vendor tools/configure.ps1 tools/configure.sh LICENSE \
    | tar -x -C "$work"
cp "$work/adapters/claude-desktop/manifest.json" "$work/manifest.json"
npx -y @anthropic-ai/mcpb@2.1.2 pack "$work" "$out/robotspeak-$version.mcpb" >/dev/null
# Notes: this version's changelog section, without its heading.
export RS_VERSION="$version"
perl -ne 'if (/^## /) { $in = /^## \Q$ENV{RS_VERSION}\E /; next } print if $in' \
    "$repo_dir/CHANGELOG.md" > "$out/notes.md"
[[ -s "$out/notes.md" ]] || { echo "No CHANGELOG.md notes for $version" >&2; exit 1; }
(cd "$out" && sha256sum "robotspeak-agents-$version.tar.gz" "robotspeak-$version.mcpb" > SHA256SUMS)
echo "$version"
