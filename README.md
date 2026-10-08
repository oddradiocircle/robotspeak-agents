# RobotSpeak Agents

Integraciones de [RobotSpeak](https://github.com/oddradiocircle/robotspeak) para agentes de IA. Con varios agentes trabajando a la vez, cada uno anuncia con una frase sonora cuándo recibió un encargo, cuándo terminó, si salió bien y si espera algo de ti.

El lenguaje (palabras, cierres, frases, marca escrita e indicativos) se define en el [diccionario de RobotSpeak](https://github.com/oddradiocircle/robotspeak/blob/main/docs/dictionary.md). Este repositorio solo conecta los agentes con ese lenguaje.

| Agente | Estado | Indicativo |
| --- | --- | --- |
| Claude Code | Plugin con hooks | 1 (do–sol, separados) |
| Codex | Plugin con adaptador propio; hooks requieren aprobación | 2 (sol–do, separados) |
| opencode | Plugin; probado con opencode 1.17.11 | 3 |
| Hermes | Plugin; validado con Hermes 0.21.4 | 4 |
| Claude Desktop y Cowork | Experimental: servidor MCP; suena solo si Claude llama la herramienta | 1 |

Los indicativos son provisionales hasta escucharlos juntos.

## Instalación rápida

| Agente | Comando |
| --- | --- |
| Claude Code | `/plugin marketplace add oddradiocircle/robotspeak-agents` y `/plugin install robotspeak@robotspeak-agents` |
| Codex | `codex plugin marketplace add oddradiocircle/robotspeak-agents` y `codex plugin add robotspeak@robotspeak-agents` |
| opencode | Ver [opencode](#opencode) |
| Hermes | `hermes plugins install oddradiocircle/robotspeak-agents --enable` |
| Claude Desktop y Cowork | Abre `robotspeak-<versión>.mcpb` del [último release](https://github.com/oddradiocircle/robotspeak-agents/releases/latest) |

La habilidad `robotspeak` controla el sonido desde cualquier agente y explica
cómo instalar la integración que falte. Los plugins de Claude Code y Codex ya la
incluyen. Para opencode, Hermes u otros agentes compatibles con
[skills.sh](https://skills.sh):

```bash
npx skills add oddradiocircle/robotspeak-agents -s robotspeak -g -a opencode hermes-agent
```

La habilidad sola no produce sonido: necesita la integración del agente.

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

## Codex

El mismo paquete incluye un manifiesto específico en `.codex-plugin/plugin.json`,
que selecciona los hooks de `adapters/codex/hooks.json`. Claude conserva sus hooks
originales. Codex usa el indicativo 2, salvo que `ROBOTSPEAK_CALLSIGN` lo cambie.

```bash
codex plugin marketplace add oddradiocircle/robotspeak-agents
codex plugin add robotspeak@robotspeak-agents
```

Para desarrollar desde una copia local, registra la ruta del repo en lugar de
`oddradiocircle/robotspeak-agents`. Codex instala una copia en su caché: después
de cambiar el adaptador, vuelve a ejecutar `codex plugin add robotspeak@robotspeak-agents`
y abre una sesión nueva.

| Evento | Frase |
| --- | --- |
| `SessionStart` | Inyecta las instrucciones, sin sonido |
| `UserPromptSubmit` | `received` (se silencia con `ROBOTSPEAK_RECEIVED=0`) |
| `Stop` | La marca de la última línea; sin marca válida, `turn` |
| `PermissionRequest` | `approval`; no aprueba la operación |
| `PreToolUse` de `request_user_input` o `request_user_input_async` | `question` |

Las preguntas en texto usan la marca `question`. Los errores que el agente puede
explicar usan `failed` o `blocked`; no se presupone un evento `StopFailure` en
Codex. Los hooks no solicitan continuar el turno ni anuncian subagentes.

**Instalar no equivale a aprobar los hooks.** Abre `/hooks` en Codex, revisa las
cinco definiciones de RobotSpeak y apruébalas. Las definiciones cambiadas necesitan
una nueva revisión. El adaptador se prueba con payloads sin sonido y el paquete se
ha instalado en un entorno temporal con Codex 0.160.1. Su runtime (`hooks/list`)
reconoce los cinco hooks sin errores de configuración. La ejecución de eventos en
una sesión real debe comprobarse después de aprobarlos.

El parser ignora marcas citadas y marcas dentro de bloques de código, incluso si
el bloque quedó sin cerrar. Solo una marca válida en la última línea no vacía del
mensaje puede declarar un resultado.

Referencias: [hooks y sus contratos](https://learn.chatgpt.com/docs/hooks),
[manifiestos y hooks de plugins](https://developers.openai.com/plugins/build/plugins).

## opencode

Un plugin de opencode en [`adapters/opencode/robotspeak.js`](adapters/opencode/robotspeak.js).
opencode carga los archivos de `~/.config/opencode/plugins/`, y el plugin necesita
el resto del repositorio a su lado. Para instalarlo:

```bash
git clone https://github.com/oddradiocircle/robotspeak-agents ~/.local/share/robotspeak-agents
mkdir -p ~/.config/opencode/plugins
ln -s ~/.local/share/robotspeak-agents/adapters/opencode/robotspeak.js ~/.config/opencode/plugins/robotspeak.js
```

Para actualizarlo, `git -C ~/.local/share/robotspeak-agents pull`. El plugin añade
las instrucciones de la marca a `instructions`, sin tocar `opencode.json`.

| Evento | Frase |
| --- | --- |
| `chat.message` de la sesión principal | `received` (se silencia con `ROBOTSPEAK_RECEIVED=0`) |
| `session.idle` tras un encargo | La marca de la última línea; sin marca válida, `turn` |
| `session.error` y después `session.idle` | `blocked`; si la persona detuvo el turno, nada |
| `permission.asked` | `approval`, también si lo pide un subagente |
| `question.asked` | `question` |

Las sesiones hijas (subagentes) no anuncian `received` ni el final del turno.
Con opencode 1.17.11 se comprobó que el plugin carga y añade las instrucciones,
y en una sesión real sonaron `received` y `blocked` (el proveedor no tenía saldo).
El final con marca está cubierto por las pruebas sin sonido; falta oírlo en una
sesión completa.

## Hermes

La raíz del repositorio es un plugin de Hermes ([`plugin.yaml`](plugin.yaml) y
[`__init__.py`](__init__.py), que carga [`adapters/hermes/plugin.py`](adapters/hermes/plugin.py)).
Así `hermes plugins install` trae también el núcleo y los motores:

```bash
hermes plugins install oddradiocircle/robotspeak-agents --enable
hermes plugins update robotspeak        # para actualizarlo
```

En otro perfil, añade `-p <perfil>`. Las instrucciones de la marca entran en el
prompt de sistema de cada sesión nueva; las sesiones reanudadas conservan su prompt.

| Hook | Frase |
| --- | --- |
| `pre_llm_call` | `received` (se silencia con `ROBOTSPEAK_RECEIVED=0`) |
| `post_llm_call` | La marca de la última línea; sin marca válida, `turn` |
| `on_human_input_request` de tipo `approval` | `approval` |
| `on_human_input_request` de tipo `clarify` | `question` |

Solo suenan las sesiones locales: `cli`, `tui` y `desktop`. Las respuestas que
Hermes envía por Telegram, Slack u otra pasarela no suenan en el computador ni
reciben la regla de la marca. `ROBOTSPEAK_HERMES_PLATFORMS` cambia la lista
(`all` para todas). Los subagentes no suenan. Un turno interrumpido no suena,
porque Hermes no llama `post_llm_call`. `hermes plugins validate` y
`hermes plugins doctor` aceptan el plugin con Hermes 0.21.4.

## Claude Desktop y Cowork

El chat de Claude Desktop y Cowork no ejecutan hooks en el computador. Por eso
la integración es un servidor MCP local: [`adapters/claude-desktop/server.js`](adapters/claude-desktop/server.js),
empaquetado como `robotspeak-<versión>.mcpb` en cada release. Ábrelo con Claude
Desktop o instálalo desde Ajustes > Extensiones. Usa el Node.js que trae Claude
Desktop.

El servidor ofrece la herramienta `robotspeak_say` y le pide a Claude llamarla al
final de cada respuesta con su estado (`done`, `review`, `question`, `failed`,
`blocked` o `turn`). **El sonido depende de que Claude la llame**: no hay un evento
que lo garantice, y `received` y `approval` no suenan. Claude Desktop puede pedir
permiso para usar la herramienta; elige permitirla siempre para no interrumpir.

- En macOS y Linux usa el mismo núcleo que los demás agentes.
- En Windows usa `tools/configure.ps1 -Say`, con preferencias en
  `%APPDATA%/robotspeak-agents/config.json`. La frase tarda varios segundos en
  sonar, porque Windows PowerShell sintetiza más lento que Perl.
- Cowork: por confirmar. Según la documentación de Anthropic, Cowork usa los
  servidores MCP locales de Claude Desktop cuando la app está abierta, pero sus
  hooks corren en una máquina virtual o en la nube, sin acceso al audio local.
- La pestaña Code de Claude Desktop usa el plugin de Claude Code en sesiones
  locales. En Windows nativo esos hooks no están soportados todavía.

## Releases

Cada versión nueva en `main` publica un release de GitHub cuando pasan todas las
pruebas. El release incluye:

- `robotspeak-<versión>.mcpb`: Claude Desktop y Cowork.
- `robotspeak-agents-<versión>.tar.gz`: el repositorio completo, para instalar a mano.
- `SHA256SUMS`: sumas para verificar las descargas.

Claude Code, Codex y Hermes se instalan y actualizan desde el repositorio.

## Plataformas

Usa los motores de RobotSpeak, fijados en [`vendor/robotspeak`](vendor/robotspeak/robotspeak-source.json): Perl en macOS y Linux. En WSL se prefiere Perl si Linux tiene reproductor (`paplay`, `pw-play` o `aplay`), porque sintetiza en unos 0,25 s frente a unos 4,5 s de PowerShell; sin reproductor Linux, usa Windows PowerShell. Los adaptadores con hooks (Claude Code, Codex, opencode y Hermes) en Windows nativo no están soportados todavía; el servidor MCP de Claude Desktop usa Windows PowerShell. La reproducción en macOS no se ha probado en un Mac.

## Configuración

La salida, el volumen, el interruptor de sonido, los estados audibles y las
partes que suenan son compartidos por todos los agentes del mismo entorno. Se
leen en cada aviso; cambiar estas preferencias no requiere cambiar los hooks ni
las instrucciones del agente.

Dentro de Claude Code, usa `/robotspeak:robotspeak off`, `/robotspeak:robotspeak on`
o `/robotspeak:robotspeak volume 50`. En Codex, invoca la habilidad con
`$robotspeak:robotspeak off`, `$robotspeak:robotspeak on` o `$robotspeak:robotspeak volume 50`.
También basta con pedirlo: «apaga RobotSpeak». Tras actualizar el plugin, recarga
sus habilidades o abre una sesión nueva para que aparezca el control.

En macOS, Linux y WSL:

```bash
bash tools/configure.sh off             # apaga los avisos de todos los agentes
bash tools/configure.sh on              # vuelve a encenderlos
bash tools/configure.sh volume 50       # volumen propio de RobotSpeak; 50 % por defecto
bash tools/configure.sh select          # muestra salidas y permite elegir por número
bash tools/configure.sh show            # preferencias guardadas
bash tools/configure.sh test done       # prueba la salida elegida, aunque done esté silenciado
bash tools/configure.sh events review,question,approval,blocked
bash tools/configure.sh events all      # restaura todos los estados
bash tools/configure.sh device default  # vuelve a seguir la salida del sistema
bash tools/configure.sh parts word+mood # sin indicativo: mensaje y cierre
bash tools/configure.sh parts mood      # solo el cierre musical
bash tools/configure.sh parts all       # indicativo, mensaje y cierre
```

Las partes son `callsign` (el indicativo, quién habla; alias `id`), `word` (el
mensaje en Morse; alias `msg`) y `mood` (el cierre, cómo salió). Se unen con `+`
y siempre suenan en ese orden. Quitar partes acorta el aviso, pero borra
diferencias: sin indicativo no sabes qué agente habla, y sin mensaje `approval`
suena igual que `blocked`. El [diccionario](https://github.com/oddradiocircle/robotspeak/blob/main/docs/dictionary.md#partes-audibles)
muestra qué frases se confunden con cada combinación.

En Windows PowerShell:

```powershell
.\tools\configure.ps1 -Off
.\tools\configure.ps1 -On
.\tools\configure.ps1 -Volume 50
.\tools\configure.ps1 -ChooseDevice
.\tools\configure.ps1 -Test done
.\tools\configure.ps1 -Events review,question,approval,blocked
.\tools\configure.ps1 -Events all
.\tools\configure.ps1 -Device default
.\tools\configure.ps1 -Parts word+mood
.\tools\configure.ps1 -Say done      # anuncio normal: respeta el interruptor y los estados
```

La selección afecta solo a RobotSpeak. No cambia la salida predeterminada ni el
volumen de las otras aplicaciones. `devices` (o `-ListDevices`) muestra también
los identificadores para seleccionar desde scripts. Los estados silenciados siguen
apareciendo en las marcas de texto; solo se omite su sonido.

El volumen acepta porcentajes enteros de 0 a 100 y se aplica a todo el PCM
de RobotSpeak, sin alterar el volumen del sistema ni el de otras aplicaciones.
El 50 % es el valor predeterminado; el 100 % conserva la amplitud original del
sintetizador, y el 0 % es silencio. El volumen final también depende del volumen
del dispositivo y del sistema. `off` conserva todas las preferencias y cancela
avisos en espera; una frase que ya suena termina. `on` recupera las preferencias
guardadas. `test` permite probarlas incluso con los avisos apagados, pero respeta
un volumen de 0 %.

Las preferencias se guardan en `$XDG_CONFIG_HOME/robotspeak-agents/config.json`,
o `~/.config/robotspeak-agents/config.json` si esa variable no existe. La herramienta
de PowerShell nativo usa `%APPDATA%/robotspeak-agents/config.json`. `ROBOTSPEAK_CONFIG`
permite elegir otro archivo. Los entornos Windows y WSL tienen rutas de preferencias
distintas por defecto; los agentes ejecutados en el mismo entorno comparten
el archivo. No se guardan preferencias en la carpeta del plugin, para conservarlas
al actualizarlo.

| Plataforma | Selección de salida |
| --- | --- |
| Windows PowerShell | Endpoint de Windows, identificado por su ID estable |
| WSL | Endpoint físico de Windows o salida virtual de Linux/WSLg |
| Linux | Nombre de sink de PulseAudio, nombre de nodo de PipeWire o nombre de PCM de ALSA |
| macOS | UID de CoreAudio; requiere Xcode Command Line Tools para compilar el componente nativo una vez |

Si la salida elegida no existe al iniciar la reproducción, Windows y macOS fallan
sin sustituirla por la salida predeterminada. PipeWire recibe las propiedades para
evitar sustitución y reconexión. PulseAudio y ALSA reciben el destino explícito;
la política del servidor o de un PCM lógico puede afectar su ruta. Usa `test` para
ver los errores de reproducción. Los avisos en segundo plano no bloquean al agente.
La selección de Windows se probó de oído desde WSL con Realtek. La reproducción
con un sink explícito de PulseAudio también se probó en WSLg; el componente macOS
y las rutas PipeWire/ALSA necesitan prueba
en el hardware correspondiente.

Variables de entorno; en Claude Code pueden ir en la sección `env` de `settings.json`.
En Codex, expórtalas antes de iniciar el proceso.
Las variables `ROBOTSPEAK_EVENTS`, `ROBOTSPEAK_DEVICE`, `ROBOTSPEAK_VOLUME` y `ROBOTSPEAK_PARTS` tienen prioridad sobre el
archivo de preferencias. `ROBOTSPEAK_RECEIVED=0` y `ROBOTSPEAK_MUTE=1` siguen teniendo
efecto aunque el estado figure en la lista de eventos habilitados.

| Variable | Predeterminado | Uso |
| --- | --- | --- |
| `ROBOTSPEAK_CALLSIGN` | El del agente | `Common`, `1`–`4` |
| `ROBOTSPEAK_RECEIVED` | `1` | `0` silencia `received` |
| `ROBOTSPEAK_MUTE` | `0` | `1` silencia todo |
| `ROBOTSPEAK_MAX_WAIT` | `20` | Segundos que una frase puede esperar en la cola |
| `ROBOTSPEAK_ENGINE` | Automático | `perl` fuerza el motor Perl |
| `ROBOTSPEAK_EVENTS` | Preferencias; todos si no hay archivo | Lista separada por comas, `all` o `none` |
| `ROBOTSPEAK_DEVICE` | Preferencias; `default` si no hay archivo | `default` o un identificador de `devices` |
| `ROBOTSPEAK_VOLUME` | Preferencias; `50` si no está guardado | Volumen propio, entero entre `0` y `100` |
| `ROBOTSPEAK_PARTS` | Preferencias; `callsign+word+mood` | Partes que suenan, unidas con `+` |
| `ROBOTSPEAK_HERMES_PLATFORMS` | `cli,tui,desktop` | Plataformas de Hermes que suenan, o `all` |
| `ROBOTSPEAK_AGENTS_DIR` | Búsqueda automática | Instalación que usa la habilidad cuando se instaló sola |
| `ROBOTSPEAK_CONFIG` | Ruta de preferencias del sistema | Archivo JSON compartido por los adaptadores |

## Desarrollo

```bash
bash tests/claude-code.sh                          # sin sonido
bash tests/codex.sh                                # sin sonido
bash tests/marker.sh                               # parser, sin sonido
bash tests/settings.sh                             # preferencias y enrutamiento, sin sonido
bash tests/volume.sh                               # amplitud y conservación del PCM, sin sonido
bash tests/queue.sh                                # apagar cancela los avisos en espera, sin sonido
bash tests/opencode.sh                             # plugin de opencode con cliente falso, sin sonido
bash tests/hermes.sh                               # plugin de Hermes con contexto falso, sin sonido
bash tests/claude-desktop.sh                       # servidor MCP por stdio, sin sonido
bash tests/skill.sh                                # habilidad instalada sola, sin sonido
bash tests/versions.sh                             # misma versión en todos los manifiestos
bash tools/sync-robotspeak.sh ~/code/robotspeak    # actualiza la copia fijada
```

Para publicar una versión, añade su sección a `CHANGELOG.md`, ejecuta
`bash tools/bump-version.sh X.Y.Z`, haz commit y push a `main`. El workflow crea
el release cuando pasan las pruebas. `bash tools/build-release.sh <carpeta>`
construye los mismos paquetes en local.

En Windows, `tests/windows-audio.ps1 -WorkDir <carpeta temporal>` comprueba sin
sonido la enumeración de salidas, las preferencias y las estructuras de WinMM.
El workflow de pruebas compila además el componente de CoreAudio en macOS.

Referencias de audio: [endpoints de Windows](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-roles-for-legacy-windows-multimedia-applications),
[selección de dispositivo en CoreAudio](https://developer.apple.com/documentation/audiotoolbox/kaudioqueueproperty_currentdevice),
[destinos de pw-play](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-cat_1.html).

MIT. Creado por Daniel Gómez / oddradiocircle.
