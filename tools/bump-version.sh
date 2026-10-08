#!/usr/bin/env bash
# Sets one version in every manifest. Pushing it to main publishes a release.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: bump-version.sh X.Y.Z' >&2; exit 1; }
grep -q "^## $version " "$repo_dir/CHANGELOG.md" || { echo "Add a '## $version (YYYY-MM-DD)' section to CHANGELOG.md first" >&2; exit 1; }
for manifest in .claude-plugin/plugin.json .codex-plugin/plugin.json adapters/claude-desktop/manifest.json; do
    RS_VERSION="$version" perl -0pi -e 's/("version"\s*:\s*")[^"]*(")/$1$ENV{RS_VERSION}$2/ or die "No version in $ARGV\n"' "$repo_dir/$manifest"
done
RS_VERSION="$version" perl -0pi -e 's/^version: .*$/version: $ENV{RS_VERSION}/m or die "No version in $ARGV\n"' "$repo_dir/plugin.yaml"
bash "$repo_dir/tests/versions.sh"
