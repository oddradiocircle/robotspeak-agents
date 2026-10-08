#!/usr/bin/env bash
# opencode adapter with a fake client and a recording say.sh. No audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree/adapters/opencode" "$work/tree/core" "$work/plugins"
cp "$repo_dir/adapters/opencode/robotspeak.js" "$work/tree/adapters/opencode/"
cp "$repo_dir/core/marker.sh" "$repo_dir/core/instructions.md" "$work/tree/core/"
cat > "$work/tree/core/say.sh" <<'SAY'
#!/usr/bin/env bash
echo "$*" >> "$RS_TEST_LOG"
SAY
# opencode loads plugins from a folder; the link must still find the core.
ln -s "$work/tree/adapters/opencode/robotspeak.js" "$work/plugins/robotspeak.js"
unset ROBOTSPEAK_CALLSIGN ROBOTSPEAK_RECEIVED
export RS_TEST_LOG="$work/said.log" RS_TEST_PLUGIN="$work/plugins/robotspeak.js" RS_TEST_ROOT="$work/tree"
node --input-type=module -e '
import { existsSync, readFileSync, writeFileSync } from "node:fs"
const { RobotSpeak } = await import(process.env.RS_TEST_PLUGIN)
const sessions = { main: {}, child: { parentID: "main" } }
const replies = {
    main: [{ info: { role: "user" }, parts: [{ type: "text", text: "[[rs:failed]]" }] },
           { info: { role: "assistant" }, parts: [{ type: "text", text: "Listo." },
                                                  { type: "tool" },
                                                  { type: "text", text: "[[rs:done]]" },
                                                  { type: "text", text: "[[rs:failed]]", synthetic: true }] }],
}
let reply = replies.main
const client = { session: {
    get: async ({ path }) => sessions[path.id] ? { data: sessions[path.id] } : Promise.reject(new Error("missing")),
    messages: async () => ({ data: reply }),
} }
const hooks = await RobotSpeak({ client })
const log = process.env.RS_TEST_LOG
const settle = () => new Promise((done) => setTimeout(done, 300))
async function expect(label, wanted, action) {
    writeFileSync(log, "")
    await action()
    await settle()
    const said = existsSync(log) ? readFileSync(log, "utf8").trim() : ""
    if (said !== wanted) { console.error(`${label}: expected "${wanted}", got "${said}"`); process.exit(1) }
}
const config = { instructions: ["AGENTS.md"] }
await hooks.config(config)
if (config.instructions.length !== 2 || config.instructions[0] !== "AGENTS.md" ||
    config.instructions[1] !== `${process.env.RS_TEST_ROOT}/core/instructions.md`) { console.error("instructions"); process.exit(1) }
const event = (type, properties) => hooks.event({ event: { type, properties } })
await expect("received", "received 3", () => hooks["chat.message"]({ sessionID: "main" }))
await expect("subagent prompt", "", () => hooks["chat.message"]({ sessionID: "child" }))
await expect("unknown session", "", () => hooks["chat.message"]({ sessionID: "gone" }))
// From here on, each turn starts with a prompt; received was checked above.
process.env.ROBOTSPEAK_RECEIVED = "0"
const turn = async (id, ...events) => {
    await hooks["chat.message"]({ sessionID: id })
    for (const [type, properties] of events) await event(type, properties)
}
await expect("done", "done 3", () => turn("main", ["session.idle", { sessionID: "main" }]))
await expect("idle twice", "", () => event("session.idle", { sessionID: "main" }))
reply = [{ info: { role: "assistant" }, parts: [{ type: "text", text: "Sin marca." }] }]
await expect("no marker", "turn 3", () => turn("main", ["session.idle", { sessionID: "main" }]))
reply = [{ info: { role: "assistant" }, parts: [{ type: "text", text: "```\n[[rs:done]]" }] }]
await expect("marker in code", "turn 3", () => turn("main", ["session.idle", { sessionID: "main" }]))
await expect("subagent idle", "", () => turn("child", ["session.idle", { sessionID: "child" }]))
await expect("created child", "", async () => {
    await event("session.created", { info: { id: "new-child", parentID: "main" } })
    await turn("new-child", ["session.idle", { sessionID: "new-child" }])
})
await expect("approval", "approval 3", () => event("permission.asked", { id: "p", sessionID: "child" }))
await expect("question", "question 3", () => event("question.asked", { id: "q", sessionID: "main" }))
await expect("api error", "blocked 3", () => turn("main",
    ["session.error", { sessionID: "main", error: { name: "APIError" } }],
    ["session.idle", { sessionID: "main" }],
    ["session.idle", { sessionID: "main" }]))
await expect("aborted", "", () => turn("main",
    ["session.error", { sessionID: "main", error: { name: "MessageAbortedError" } }],
    ["session.idle", { sessionID: "main" }]))
await expect("unrelated event", "", () => event("message.updated", {}))
await expect("received off", "", () => hooks["chat.message"]({ sessionID: "main" }))
process.env.ROBOTSPEAK_CALLSIGN = "Common"
await expect("callsign", "approval Common", () => event("permission.asked", { id: "p", sessionID: "main" }))
'
echo 'opencode adapter: all checks passed'
