---
name: control
description: Turn RobotSpeak audio notifications on or off, adjust their volume, or inspect their saved preferences when the user asks to control RobotSpeak.
---

Run the requested control using `scripts/configure.sh` beside this skill. Resolve
its full path from this SKILL.md's location, so it works from any repository.

- `off`: disable sound for both Claude Code and Codex, preserving the device,
  volume and event selections.
- `on`: enable sound with those saved preferences.
- `volume N`: save an integer percentage from 0 to 100; the default is 50.
- `show`: display saved preferences without changing them.
- `test STATE`: explicitly play that state on the saved output at the saved
  volume, even when ordinary announcements are disabled.

For example, invoke `bash /full/path/to/skills/control/scripts/configure.sh off`.
Pass the action and value as separate quoted arguments. With no requested action,
show preferences. Do not change system volume or disable the plugin's hooks.
Respect the environment's approval requirements for changing user preferences.
Confirm the resulting enabled state or volume briefly. A phrase already playing
finishes; `off` cancels announcements still waiting in the queue.
