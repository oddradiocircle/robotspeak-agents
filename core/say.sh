#!/usr/bin/env bash
# Plays a dictionary phrase in the background and returns at once.
# Phrases queue behind a lock so agents never talk over each other;
# one that waited longer than ROBOTSPEAK_MAX_WAIT seconds is dropped.
set -u
core_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-}" in
    received) word=RCV mood=Neutral ;;
    done)     word=OK  mood=Satisfied ;;
    review)   word=OK  mood=Doubtful ;;
    question) word=K   mood=Curious ;;
    approval) word=K   mood=Concerned ;;
    failed)   word=ERR mood=Apologetic ;;
    blocked)  word=ERR mood=Concerned ;;
    turn)     word=K   mood=Neutral ;;
    *) exit 0 ;;
esac
[[ -n "${ROBOTSPEAK_DEBUG:-}" ]] && echo "$1 $word $mood ${2:-}" >&2
[[ "${ROBOTSPEAK_MUTE:-0}" == 1 ]] && exit 0
callsign="${2:-${ROBOTSPEAK_CALLSIGN:-Common}}"
# In WSL the Perl engine starts far faster than Windows PowerShell; use it when
# Linux has a player, such as paplay through WSLg.
if [[ -z "${ROBOTSPEAK_ENGINE:-}" ]] && command -v wslpath >/dev/null; then
    for player in paplay pw-play aplay; do
        if command -v "$player" >/dev/null; then export ROBOTSPEAK_ENGINE=perl; break; fi
    done
fi
lock="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/robotspeak-agents.lock"
nohup perl -MFcntl=:flock -e '
    my ($lock, $max_wait, @command) = @ARGV;
    my $queued = time;
    open(my $fh, ">>", $lock) or exit 1;
    flock($fh, LOCK_EX) or exit 1;
    exit 0 if time - $queued > $max_wait;
    exit(system(@command) >> 8);
' "$lock" "${ROBOTSPEAK_MAX_WAIT:-20}" \
    bash "$core_dir/../vendor/robotspeak/speak.sh" \
    -Word "$word" -Mood "$mood" -Callsign "$callsign" -PauseMs 0 \
    </dev/null >/dev/null 2>&1 &
