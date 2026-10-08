"""Hermes plugin: maps agent hooks to dictionary phrases.

Hermes speaks with callsign 4 unless ROBOTSPEAK_CALLSIGN says otherwise.
Only local sessions sound: replies sent to Telegram or Slack do not reach
the person at this computer. ROBOTSPEAK_HERMES_PLATFORMS changes that list.
"""
import os
import subprocess
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCAL_PLATFORMS = ("cli", "tui", "desktop")


def _local(platform):
    chosen = os.environ.get("ROBOTSPEAK_HERMES_PLATFORMS", ",".join(LOCAL_PLATFORMS))
    return chosen == "all" or (platform or "") in chosen.split(",")


def _say(phrase=None, message=None):
    """With a message, the phrase comes from its marker, read by the shared parser."""
    callsign = os.environ.get("ROBOTSPEAK_CALLSIGN", "4")
    if message is None:
        command = ["bash", str(ROOT / "core" / "say.sh"), phrase, callsign]
    else:
        command = ["bash", "-c", 'bash "$1/core/say.sh" "$(bash "$1/core/marker.sh")" "$2"',
                   "robotspeak", str(ROOT), callsign]
    try:
        child = subprocess.Popen(command, stdin=subprocess.PIPE if message is not None else subprocess.DEVNULL,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return

    # say.sh returns at once; this thread only feeds the message and reaps the child.
    def finish():
        try:
            child.communicate(None if message is None else message.encode("utf-8"), timeout=30)
        except Exception:
            child.kill()

    threading.Thread(target=finish, daemon=True).start()


def _instructions(session):
    if not _local(session.get("platform")):
        return ""
    return (ROOT / "core" / "instructions.md").read_text(encoding="utf-8")


def _received(platform="", **_):
    if os.environ.get("ROBOTSPEAK_RECEIVED", "1") == "1" and _local(platform):
        _say("received")


def _finished(assistant_response="", platform="", **_):
    if _local(platform):
        _say(message=str(assistant_response or ""))


def _human_input(kind="", platform="", **_):
    if _local(platform) and kind in ("approval", "clarify"):
        _say("approval" if kind == "approval" else "question")


def register(ctx):
    ctx.register_system_prompt_section("robotspeak.marker", _instructions, max_chars=2000)
    ctx.register_hook("pre_llm_call", _received)
    ctx.register_hook("post_llm_call", _finished)
    ctx.register_hook("on_human_input_request", _human_input)
