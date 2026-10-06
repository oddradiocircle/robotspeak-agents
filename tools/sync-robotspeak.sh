#!/usr/bin/env bash
# Copies the RobotSpeak engines from a checkout's HEAD and records their origin.
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo 'Usage: bash tools/sync-robotspeak.sh <robotspeak-checkout>' >&2
    exit 1
fi
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$1"
vendor_dir="$repo_dir/vendor/robotspeak"
commit="$(git -C "$source_dir" rev-parse HEAD)"
files=(scripts/robot-voice.ps1 scripts/robot-voice.pl scripts/speak.sh)
entries=()
for path in "${files[@]}"; do
    git -C "$source_dir" show "HEAD:$path" > "$vendor_dir/${path##*/}"
    hash="$(sha256sum "$vendor_dir/${path##*/}")"
    entries+=("    {\"path\": \"$path\", \"sha256\": \"${hash%% *}\"}")
done
git -C "$source_dir" show HEAD:LICENSE > "$vendor_dir/LICENSE"
{
    printf '{\n  "repository": "https://github.com/oddradiocircle/robotspeak",\n  "commit": "%s",\n  "files": [\n' "$commit"
    (IFS=$'\n'; printf '%s\n' "${entries[*]}" | sed '$!s/$/,/')
    printf '  ]\n}\n'
} > "$vendor_dir/robotspeak-source.json"
