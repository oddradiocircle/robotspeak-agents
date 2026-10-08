// opencode plugin: maps session events to dictionary phrases.
// opencode speaks with callsign 3 unless ROBOTSPEAK_CALLSIGN says otherwise.
import { spawn } from "node:child_process"
import { realpathSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// Resolve links, so a plugin linked into ~/.config/opencode/plugins finds the core.
const root = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "..", "..")

// With a message, the phrase comes from its marker, read by the shared parser.
function say(phrase, message) {
    const callsign = process.env.ROBOTSPEAK_CALLSIGN || "3"
    const command = message === undefined
        ? [join(root, "core", "say.sh"), phrase, callsign]
        : ["-c", 'bash "$1/core/say.sh" "$(bash "$1/core/marker.sh")" "$2"', "robotspeak", root, callsign]
    try {
        const child = spawn("bash", command, { stdio: [message === undefined ? "ignore" : "pipe", "ignore", "ignore"] })
        child.on("error", () => {})
        if (message !== undefined) {
            child.stdin.on("error", () => {})
            child.stdin.end(message)
        }
        child.unref()
    } catch {}
}

export const RobotSpeak = async ({ client }) => {
    const children = new Map()
    const failures = new Map()
    // A session can go idle twice after one prompt, as after an API error.
    const awaiting = new Set()
    // Subagents run in child sessions; only what reaches the person sounds.
    async function isChild(id) {
        if (!id) return true
        if (!children.has(id)) {
            const session = await client.session.get({ path: { id } }).catch(() => undefined)
            if (!session?.data) return true
            children.set(id, Boolean(session.data.parentID))
        }
        return children.get(id)
    }
    return {
        config: async (config) => {
            config.instructions = [...(config.instructions ?? []), join(root, "core", "instructions.md")]
        },
        // Awaited inside the prompt path: never wait for the session lookup here.
        "chat.message": async ({ sessionID }) => {
            awaiting.add(sessionID)
            if (process.env.ROBOTSPEAK_RECEIVED === "0") return
            isChild(sessionID).then((child) => child || say("received"), () => {})
        },
        event: async ({ event }) => {
            try {
                const properties = event.properties ?? {}
                const id = properties.sessionID
                if (event.type === "session.created" && properties.info?.parentID) children.set(properties.info.id, true)
                // A subagent's request still waits for the person.
                else if (event.type === "permission.asked") say("approval")
                else if (event.type === "question.asked") say("question")
                else if (event.type === "session.error" && id) failures.set(id, properties.error?.name ?? "UnknownError")
                else if (event.type === "session.idle") {
                    const failure = failures.get(id)
                    failures.delete(id)
                    if (!awaiting.delete(id) || await isChild(id)) return
                    // The person stopped the turn; there is nothing to announce.
                    if (failure === "MessageAbortedError") return
                    if (failure) return say("blocked")
                    const messages = await client.session.messages({ path: { id } })
                    const last = (messages.data ?? []).findLast((message) => message.info?.role === "assistant")
                    const text = (last?.parts ?? [])
                        .filter((part) => part.type === "text" && !part.synthetic)
                        .map((part) => part.text)
                        .join("\n")
                    say(undefined, text)
                }
            } catch {}
        },
    }
}
