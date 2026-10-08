---
name: robotspeak
description: Control RobotSpeak audio notifications (on, off, volume, audible states, which parts of a phrase sound) or install RobotSpeak for this agent when the user asks to hear when the agent finishes, fails or needs them.
---

Run the requested control using `scripts/configure.sh` beside this skill. Resolve
its full path from this SKILL.md's location, so it works from any repository.

- `off`: disable sound for every agent, preserving the device, volume, parts and
  event selections.
- `on`: enable sound with those saved preferences.
- `volume N`: save an integer percentage from 0 to 100; the default is 50.
- `parts P`: choose which parts of each phrase sound. Join `callsign` (who
  speaks), `word` (the message) and `mood` (how it went) with `+`, for example
  `word+mood` or `mood`; `all` restores the three. They always sound in that order.
- `events all|none|state,state`: choose the audible states (received, done,
  review, question, approval, failed, blocked, turn).
- `show`: display saved preferences without changing them.
- `test STATE`: explicitly play that state on the saved output at the saved
  volume, even when ordinary announcements are disabled.

For example, invoke `bash /full/path/to/skills/robotspeak/scripts/configure.sh off`.
Pass the action and value as separate quoted arguments. With no requested action,
show preferences. Do not change system volume or disable the agent's hooks.
Respect the environment's approval requirements for changing user preferences.
Confirm the resulting state briefly. A phrase already playing finishes; `off`
cancels announcements still waiting in the queue.

## Install

If the script exits with code 3, RobotSpeak is not installed for this agent.
Show the user the matching command, explain that it installs hooks that run on
every turn, and run it only after they agree:

- Claude Code: `/plugin marketplace add oddradiocircle/robotspeak-agents`, then
  `/plugin install robotspeak@robotspeak-agents`.
- Codex: `codex plugin marketplace add oddradiocircle/robotspeak-agents`, then
  `codex plugin add robotspeak@robotspeak-agents`; the user approves the hooks in `/hooks`.
- Hermes: `hermes plugins install oddradiocircle/robotspeak-agents --enable`.
- opencode: `git clone https://github.com/oddradiocircle/robotspeak-agents ~/.local/share/robotspeak-agents`,
  then `mkdir -p ~/.config/opencode/plugins` and
  `ln -s ~/.local/share/robotspeak-agents/adapters/opencode/robotspeak.js ~/.config/opencode/plugins/robotspeak.js`.
- Claude Desktop and Cowork: download `robotspeak-<version>.mcpb` from
  https://github.com/oddradiocircle/robotspeak-agents/releases/latest and open it.

A new session is needed before the agent starts sounding.
