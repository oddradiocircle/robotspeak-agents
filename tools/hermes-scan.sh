#!/usr/bin/env bash
# Run the Hermes install scanner on the tracked files, as `hermes plugins install` would.
# A community plugin installs only with a "safe" verdict: one high finding blocks it.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
agent_dir="${HERMES_AGENT_DIR:-$HOME/.hermes/hermes-agent}"
python=""
for candidate in "$agent_dir/venv/bin/python" "$agent_dir/.venv/bin/python"; do
    [[ -x "$candidate" ]] && { python="$candidate"; break; }
done
[[ -n "$python" && -f "$agent_dir/tools/plugin_guard.py" ]] || {
    echo "hermes-scan: Hermes not found; set HERMES_AGENT_DIR" >&2
    exit 2
}
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The working tree, uncommitted edits included, as the clone would hold it.
mkdir "$work/robotspeak-agents"
git -C "$repo_dir" ls-files -z --cached --others --exclude-standard |
    (cd "$repo_dir" && tar --null -T - -cf -) | tar -xf - -C "$work/robotspeak-agents"
cd "$agent_dir"
"$python" -c '
import sys
from pathlib import Path
from tools.plugin_guard import format_scan_report, scan_plugin, should_allow_plugin_install
result = scan_plugin(Path(sys.argv[1]), "oddradiocircle/robotspeak-agents")
allowed, reason = should_allow_plugin_install(result)
print(format_scan_report(result))
print(reason)
sys.exit(0 if allowed else 1)
' "$work/robotspeak-agents"
