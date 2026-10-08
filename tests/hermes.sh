#!/usr/bin/env bash
# Hermes adapter with a fake plugin context and a recording say.sh. No audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree/adapters/hermes" "$work/tree/core" "$work/plugins"
cp "$repo_dir/__init__.py" "$repo_dir/plugin.yaml" "$work/tree/"
cp "$repo_dir/adapters/hermes/plugin.py" "$work/tree/adapters/hermes/"
cp "$repo_dir/core/marker.sh" "$repo_dir/core/instructions.md" "$work/tree/core/"
cat > "$work/tree/core/say.sh" <<'SAY'
#!/usr/bin/env bash
echo "$*" >> "$RS_TEST_LOG"
SAY
# A plugin linked into ~/.hermes/plugins must still find the core.
ln -s "$work/tree" "$work/plugins/robotspeak"
unset ROBOTSPEAK_CALLSIGN ROBOTSPEAK_RECEIVED ROBOTSPEAK_HERMES_PLATFORMS
export RS_TEST_LOG="$work/said.log" RS_TEST_PLUGIN="$work/plugins/robotspeak"
python3 -I - <<'PY'
import importlib.util, os, sys, time
from pathlib import Path

plugin = Path(os.environ["RS_TEST_PLUGIN"])
spec = importlib.util.spec_from_file_location("robotspeak", plugin / "__init__.py",
                                              submodule_search_locations=[str(plugin)])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Context:
    def __init__(self):
        self.hooks, self.sections = {}, {}
    def register_hook(self, name, callback):
        self.hooks[name] = callback
    def register_system_prompt_section(self, id, content, position="after_memory", max_chars=4000):
        self.sections[id] = (content, max_chars)

ctx = Context()
module.register(ctx)
log = Path(os.environ["RS_TEST_LOG"])

def expect(label, wanted, hook, **payload):
    log.write_text("")
    ctx.hooks[hook](**payload)
    deadline = time.time() + 3
    while wanted and not log.read_text().strip() and time.time() < deadline:
        time.sleep(0.02)
    if not wanted:
        time.sleep(0.3)
    said = log.read_text().strip()
    if said != wanted:
        sys.exit(f"{label}: expected {wanted!r}, got {said!r}")

content, limit = ctx.sections["robotspeak.marker"]
text = content({"platform": "cli", "session_id": "s"})
if "[[rs:<clave>]]" not in text or len(text) > limit:
    sys.exit("instructions")
if content({"platform": "telegram"}) != "":
    sys.exit("instructions reached a remote platform")
if set(ctx.hooks) != {"pre_llm_call", "post_llm_call", "on_human_input_request"}:
    sys.exit("hooks")
final = "Listo.\n\n[[rs:done]]"
expect("received", "received 4", "pre_llm_call", platform="cli", session_id="s", user_message="hola")
expect("done", "done 4", "post_llm_call", platform="tui", assistant_response=final)
expect("no marker", "turn 4", "post_llm_call", platform="cli", assistant_response="Sin marca.")
expect("marker in code", "turn 4", "post_llm_call", platform="cli", assistant_response="```\n[[rs:done]]")
expect("empty reply", "turn 4", "post_llm_call", platform="cli", assistant_response=None)
expect("approval", "approval 4", "on_human_input_request", kind="approval", platform="cli", prompt="rm?")
expect("clarify", "question 4", "on_human_input_request", kind="clarify", platform="desktop", prompt="¿Cuál?")
expect("sudo", "", "on_human_input_request", kind="sudo", platform="cli", prompt="password")
expect("subagent", "", "post_llm_call", platform="subagent", assistant_response=final)
expect("gateway", "", "post_llm_call", platform="telegram", assistant_response=final)
os.environ["ROBOTSPEAK_HERMES_PLATFORMS"] = "all"
expect("all platforms", "done 4", "post_llm_call", platform="telegram", assistant_response=final)
del os.environ["ROBOTSPEAK_HERMES_PLATFORMS"]
os.environ["ROBOTSPEAK_RECEIVED"] = "0"
expect("received off", "", "pre_llm_call", platform="cli")
os.environ["ROBOTSPEAK_CALLSIGN"] = "Common"
expect("callsign", "done Common", "post_llm_call", platform="cli", assistant_response=final)
PY
echo 'Hermes adapter: all checks passed'
