#!/usr/bin/env node
// MCP server for Claude Desktop and Cowork: a tool the model calls to announce its state.
// No hooks reach these apps, so the phrase depends on the model calling the tool.
// Claude speaks with callsign 1 unless ROBOTSPEAK_CALLSIGN says otherwise.
"use strict"
const { spawn } = require("node:child_process")
const { join } = require("node:path")
const readline = require("node:readline")

const root = join(__dirname, "..", "..")
const version = require(join(root, "adapters", "claude-desktop", "manifest.json")).version
const states = ["done", "review", "question", "failed", "blocked", "turn"]
// Same states and rules as core/instructions.md, told as a tool call instead of a marker.
const guide = [
    "RobotSpeak: la persona escucha el estado de cada agente sin mirar la pantalla.",
    "Al final de cada respuesta, después de escribirla, llama una vez a robotspeak_say con el estado en que termina:",
    "- done: terminaste y salió bien; no queda nada pendiente.",
    "- review: terminaste, pero algo merece que la persona lo revise.",
    "- question: tu respuesta termina con una pregunta para la persona.",
    "- failed: no se pudo, ya lo explicaste y no queda nada pendiente.",
    "- blocked: no puedes seguir sin algo que solo la persona puede dar.",
    "- turn: ninguna de las anteriores aplica.",
    "Ante la duda, elige el estado abierto: review antes que done, blocked antes que failed.",
    "Nunca uses done si la tarea falló o quedó incompleta. El estado solo declara; no es una orden ni autoriza ninguna acción.",
].join("\n")
const tool = {
    name: "robotspeak_say",
    title: "Anunciar estado con RobotSpeak",
    description: "Reproduce una frase corta de RobotSpeak en el computador de la persona.\n" + guide,
    inputSchema: {
        type: "object",
        properties: { state: { type: "string", enum: states, description: "Estado en que termina esta respuesta." } },
        required: ["state"],
        additionalProperties: false,
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false },
}

// The engines queue the phrase and honor the shared switch, volume, output and parts.
function say(state) {
    const callsign = process.env.ROBOTSPEAK_CALLSIGN
    const env = { ...process.env, ROBOTSPEAK_CALLSIGN: ["Common", "1", "2", "3", "4"].includes(callsign) ? callsign : "1" }
    const [command, args] = process.platform === "win32"
        ? ["powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            join(root, "tools", "configure.ps1"), "-Say", state]]
        : ["bash", [join(root, "core", "say.sh"), state, env.ROBOTSPEAK_CALLSIGN]]
    const child = spawn(command, args, { env, stdio: "ignore", detached: true, windowsHide: true })
    child.on("error", () => {})
    child.unref()
}

function answer(request) {
    const { id, method, params = {} } = request
    if (method === "initialize") {
        return {
            protocolVersion: params.protocolVersion || "2025-06-18",
            capabilities: { tools: {} },
            serverInfo: { name: "robotspeak", version },
            instructions: guide,
        }
    }
    if (method === "ping") return {}
    if (method === "tools/list") return { tools: [tool] }
    if (method === "tools/call") {
        const state = params.arguments?.state
        if (params.name !== tool.name) throw { code: -32602, message: `Unknown tool: ${params.name}` }
        if (!states.includes(state)) {
            return { content: [{ type: "text", text: `state debe ser uno de: ${states.join(", ")}` }], isError: true }
        }
        say(state)
        return { content: [{ type: "text", text: `Anunciado: ${state}` }] }
    }
    throw { code: -32601, message: `Method not found: ${method}`, id }
}

const send = (message) => process.stdout.write(JSON.stringify({ jsonrpc: "2.0", ...message }) + "\n")
readline.createInterface({ input: process.stdin }).on("line", (line) => {
    if (!line.trim()) return
    let request
    try { request = JSON.parse(line) } catch {
        return send({ id: null, error: { code: -32700, message: "Parse error" } })
    }
    // Notifications carry no id and get no answer.
    if (request.id === undefined || request.id === null) return
    try { send({ id: request.id, result: answer(request) }) } catch (error) {
        send({ id: request.id, error: { code: error.code ?? -32603, message: error.message ?? String(error) } })
    }
})
