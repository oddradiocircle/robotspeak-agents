#!/usr/bin/env bash
# The skill installed alone (npx skills) finds an install, or says how to get one.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$work/skills"
cp -R "$repo_dir/skills/robotspeak" "$work/skills/"
skill="$work/skills/robotspeak/scripts/configure.sh"
export HOME="$work/home" ROBOTSPEAK_CONFIG="$work/config.json"
unset ROBOTSPEAK_AGENTS_DIR HERMES_HOME XDG_CONFIG_HOME XDG_DATA_HOME
status=0; bash "$skill" show >/dev/null 2>"$work/err" || status=$?
[[ "$status" == 3 ]] && grep -q 'not installed' "$work/err" || { echo 'Missing install not reported'; exit 1; }
# Each place an agent keeps the runtime is found.
runtime() { mkdir -p "$1"; cp -R "$repo_dir/core" "$repo_dir/tools" "$repo_dir/vendor" "$1/"; }
runtime "$HOME/.claude/plugins/cache/robotspeak-agents/robotspeak/0.3.0"
bash "$skill" volume 30 >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective | sed -n 3p)" == 30 ]]
rm -rf "$HOME/.claude"
runtime "$HOME/.hermes/plugins/robotspeak"
bash "$skill" parts mood >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective | sed -n 5p)" == mood ]]
rm -rf "$HOME/.hermes"
runtime "$work/opencode-runtime"
mkdir -p "$work/opencode-runtime/adapters/opencode" "$HOME/.config/opencode/plugins"
cp "$repo_dir/adapters/opencode/robotspeak.js" "$work/opencode-runtime/adapters/opencode/"
ln -s "$work/opencode-runtime/adapters/opencode/robotspeak.js" "$HOME/.config/opencode/plugins/robotspeak.js"
bash "$skill" off >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective | sed -n 4p)" == 0 ]]
rm -rf "$HOME/.config"
ROBOTSPEAK_AGENTS_DIR="$repo_dir" bash "$skill" on >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective | sed -n 4p)" == 1 ]]
echo 'Standalone skill: all checks passed'
