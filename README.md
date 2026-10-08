# RobotSpeak Agents

Integraciones de [RobotSpeak](https://github.com/oddradiocircle/robotspeak) para agentes de IA. Con varios agentes trabajando a la vez, cada uno anuncia con una frase sonora cuándo recibió un encargo, cuándo terminó, si salió bien y si espera algo de ti.

El lenguaje (palabras, cierres, frases, marca escrita e indicativos) se define en el [diccionario de RobotSpeak](https://github.com/oddradiocircle/robotspeak/blob/main/docs/dictionary.md). Este repositorio solo conecta los agentes con ese lenguaje.

| Agente | Estado | Indicativo |
| --- | --- | --- |
| Claude Code | Plugin con hooks | 1 (do–sol, separados) |
| Codex | Plugin con adaptador propio; hooks requieren aprobación | 2 (sol–do, separados) |
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

## Plataformas

Usa los motores de RobotSpeak, fijados en [`vendor/robotspeak`](vendor/robotspeak/robotspeak-source.json): Perl en macOS y Linux. En WSL se prefiere Perl si Linux tiene reproductor (`paplay`, `pw-play` o `aplay`), porque sintetiza en unos 0,25 s frente a unos 4,5 s de PowerShell; sin reproductor Linux, usa Windows PowerShell. Los adaptadores de Claude Code y Codex nativos en Windows no están soportados todavía. La reproducción en macOS no se ha probado en un Mac.

## Configuración

La salida, el volumen, el interruptor de sonido y los estados audibles son
compartidos por Claude Code y Codex. Se leen en cada aviso; cambiar estas preferencias no requiere cambiar
los hooks ni las instrucciones del agente.

Dentro de Claude Code, usa `/robotspeak:control off`, `/robotspeak:control on`
o `/robotspeak:control volume 50`. En Codex, invoca la habilidad con
`$robotspeak:control off`, `$robotspeak:control on` o `$robotspeak:control volume 50`.
Tras actualizar el plugin, recarga sus habilidades o abre una sesión nueva para
que aparezca el control.

En macOS, Linux y WSL:

```bash
bash tools/configure.sh off             # apaga los avisos de ambos agentes
bash tools/configure.sh on              # vuelve a encenderlos
bash tools/configure.sh volume 50       # volumen propio de RobotSpeak; 50 % por defecto
bash tools/configure.sh select          # muestra salidas y permite elegir por número
bash tools/configure.sh show            # preferencias guardadas
bash tools/configure.sh test done       # prueba la salida elegida, aunque done esté silenciado
bash tools/configure.sh events review,question,approval,blocked
bash tools/configure.sh events all      # restaura todos los estados
bash tools/configure.sh device default  # vuelve a seguir la salida del sistema
```

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
distintas por defecto; Claude Code y Codex ejecutados en el mismo entorno comparten
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
Las variables `ROBOTSPEAK_EVENTS`, `ROBOTSPEAK_DEVICE` y `ROBOTSPEAK_VOLUME` tienen prioridad sobre el
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
| `ROBOTSPEAK_CONFIG` | Ruta de preferencias del sistema | Archivo JSON compartido por los adaptadores |

## Desarrollo

```bash
bash tests/claude-code.sh                          # sin sonido
bash tests/codex.sh                                # sin sonido
bash tests/marker.sh                               # parser, sin sonido
bash tests/settings.sh                             # preferencias y enrutamiento, sin sonido
bash tests/volume.sh                               # amplitud y conservación del PCM, sin sonido
bash tests/queue.sh                                # apagar cancela los avisos en espera, sin sonido
bash tools/sync-robotspeak.sh ~/code/robotspeak    # actualiza la copia fijada
```

En Windows, `tests/windows-audio.ps1 -WorkDir <carpeta temporal>` comprueba sin
sonido la enumeración de salidas, las preferencias y las estructuras de WinMM.
El workflow de pruebas compila además el componente de CoreAudio en macOS.

Referencias de audio: [endpoints de Windows](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-roles-for-legacy-windows-multimedia-applications),
[selección de dispositivo en CoreAudio](https://developer.apple.com/documentation/audiotoolbox/kaudioqueueproperty_currentdevice),
[destinos de pw-play](https://pipewire.pages.freedesktop.org/pipewire/page_man_pw-cat_1.html).

MIT. Creado por Daniel Gómez / oddradiocircle.
