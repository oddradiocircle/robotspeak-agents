#!/usr/bin/env bash
# Invocable skill entrypoint, independent of the current working directory.
# Inside a plugin the runtime is three folders up; installed alone (npx skills),
# the skill uses the first RobotSpeak Agents install it finds.
set -euo pipefail
skill_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
opencode_plugin="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/plugins/robotspeak.js"
candidates=("${ROBOTSPEAK_AGENTS_DIR:-}" "$skill_dir/../..")
[[ -e "$opencode_plugin" ]] && candidates+=("$(dirname -- "$(perl -MCwd=abs_path -e 'print abs_path(shift)' "$opencode_plugin")")/../..")
candidates+=("${HERMES_HOME:-$HOME/.hermes}/plugins/robotspeak" "${XDG_DATA_HOME:-$HOME/.local/share}/robotspeak-agents")
# Plugin caches keep one folder per version; prefer the newest.
for cache in "$HOME/.claude/plugins/cache/robotspeak-agents/robotspeak" "$HOME/.codex/plugins/cache/robotspeak-agents/robotspeak"; do
    [[ -d "$cache" ]] || continue
    while IFS= read -r version; do candidates+=("$version"); done < <(perl -e '
        my $dir = shift; opendir(my $dh, $dir) or exit;
        sub rank { join "", map { sprintf "%09d", $_ // 0 } ($_[0] =~ /(\d+)/g)[0..2] }
        print "$dir/$_\n" for sort { rank($b) cmp rank($a) } grep { !/^\./ && -d "$dir/$_" } readdir $dh;
    ' "$cache")
done
for dir in "${candidates[@]}"; do
    if [[ -n "$dir" && -f "$dir/tools/configure.sh" && -f "$dir/core/settings.pl" ]]; then
        exec bash "$dir/tools/configure.sh" "$@"
    fi
done
echo 'RobotSpeak Agents is not installed for this agent. See "Install" in SKILL.md.' >&2
exit 3
