# Cambios

Cada versión publicada tiene su sección aquí. Al subir la versión con
`tools/bump-version.sh`, la integración continua crea el release de GitHub
con estas notas y los paquetes instalables.

## 0.3.0 (2026-10-08)

- Nuevos agentes: opencode (indicativo 3), Hermes (indicativo 4) y, en fase
  experimental, Claude Desktop y Cowork mediante un servidor MCP (`.mcpb`).
- Nueva preferencia `parts`: elige qué partes de cada frase suenan
  (`callsign`, `word`, `mood`), por ejemplo `word+mood` o solo `mood`.
- La habilidad `control` pasa a llamarse `robotspeak` (`/robotspeak:robotspeak`
  en Claude Code). Funciona también instalada sola con `npx skills`.
- `configure.ps1 -Say` anuncia un estado en Windows respetando el interruptor,
  los estados audibles y la cola.
- Motores de RobotSpeak actualizados a b28a7b4: síntesis más rápida con el
  mismo PCM, `-Parts` y Perl por defecto en WSL cuando hay reproductor Linux.
- Releases automáticos con paquetes instalables y sumas SHA-256.

## 0.2.0 (2026-10-08)

- Adaptador de Codex, preferencias compartidas (salida, volumen, interruptor y
  estados audibles) y selección de dispositivo de audio.

## 0.1.0 (2026-10-05)

- Plugin de Claude Code que reproduce las frases del diccionario.
