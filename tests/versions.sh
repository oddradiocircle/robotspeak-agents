#!/usr/bin/env bash
# Every manifest declares the same version, and the changelog describes it.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
json_version() { perl -MJSON::PP -0777 -ne 'print decode_json($_)->{version} // ""' "$repo_dir/$1"; }
version="$(json_version .claude-plugin/plugin.json)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version: $version"; exit 1; }
for manifest in .codex-plugin/plugin.json adapters/claude-desktop/manifest.json; do
    [[ "$(json_version "$manifest")" == "$version" ]] || { echo "$manifest is not $version"; exit 1; }
done
[[ "$(sed -n 's/^version: //p' "$repo_dir/plugin.yaml")" == "$version" ]] || { echo "plugin.yaml is not $version"; exit 1; }
grep -q "^## $version " "$repo_dir/CHANGELOG.md" || { echo "CHANGELOG.md has no $version section"; exit 1; }
echo "Versions: all manifests at $version"
