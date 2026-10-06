# RobotSpeak Agents

Integraciones de [RobotSpeak](https://github.com/oddradiocircle/robotspeak) para agentes de IA. Con varios agentes trabajando a la vez, cada uno anuncia con una frase sonora cuándo recibió un encargo, cuándo terminó, si salió bien y si espera algo de ti.

El lenguaje (palabras, cierres, frases, marca escrita e indicativos) se define en el [diccionario de RobotSpeak](https://github.com/oddradiocircle/robotspeak/blob/main/docs/dictionary.md). Este repositorio solo conecta los agentes con ese lenguaje.

| Agente | Estado | Indicativo |
| --- | --- | --- |
| Claude Code | Plugin con hooks | 1 (do–sol, separados) |
| Codex | Pendiente | 2 |
| opencode | Pendiente | 3 |
| Hermes | Pendiente | 4 |

Los indicativos son provisionales hasta escucharlos juntos.

## Cómo funciona

1. Al iniciar la sesión, el agente recibe la regla del diccionario: terminar cada respuesta con `[[rs:<clave>]]` en la última línea ([texto exacto](core/instructions.md)).
2. Los eventos del agente se traducen a frases. Las que dependen del agente salen de su marca; las demás, del propio evento.
3. `core/say.sh` reproduce la frase en segundo plano. Una cola evita que dos agentes hablen a la vez, y descarta la frase que esperó más de 20 segundos.

## Claude Code

| Evento | Frase |
| --- | --- |
| `UserPromptSubmit` escrito por la persona | `received` |
| `Stop` | La marca de la última línea; sin marca válida, `turn` |
| `StopFailure` (error de la API) | `blocked` |
| `PermissionRequest` | `approval` |
| `PreToolUse` de `AskUserQuestion`, `Notification` de tipo `elicitation_dialog` | `question` |

Los subagentes no suenan: solo cuenta lo que llega a la persona.

Instalación:

```text
/plugin marketplace add oddradiocircle/robotspeak-agents
/plugin install robotspeak@robotspeak-agents
```

Para probarlo desde una copia local, `claude --plugin-dir /ruta/a/robotspeak-agents`.

## Plataformas

Usa los motores de RobotSpeak, fijados en [`vendor/robotspeak`](vendor/robotspeak/robotspeak-source.json): Perl en macOS y Linux, Windows PowerShell en WSL. En WSL se prefiere Perl si Linux tiene reproductor (`paplay`, `pw-play` o `aplay`), porque sintetiza en unos 0,25 s frente a unos 4,5 s de PowerShell. Claude Code nativo en Windows no está soportado todavía.

## Configuración

Variables de entorno; en Claude Code pueden ir en la sección `env` de `settings.json`.

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `ROBOTSPEAK_CALLSIGN` | El del agente | `Common`, `1`–`4` |
| `ROBOTSPEAK_RECEIVED` | `1` | `0` silencia `received` |
| `ROBOTSPEAK_MUTE` | `0` | `1` silencia todo |
| `ROBOTSPEAK_MAX_WAIT` | `20` | Segundos que una frase puede esperar en la cola |
| `ROBOTSPEAK_ENGINE` | Automático | `perl` fuerza el motor Perl |

## Desarrollo

```bash
bash tests/claude-code.sh                          # sin sonido
bash tools/sync-robotspeak.sh ~/code/robotspeak    # actualiza la copia fijada
```

MIT. Creado por Daniel Gómez / oddradiocircle.
