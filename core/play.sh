#!/usr/bin/env bash
# Synchronous playback; callers hold the shared lock or run an explicit test.
set -euo pipefail
core_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
word="$1" mood="$2" callsign="$3" device="$4" volume="${5:-50}"
[[ "$volume" =~ ^[0-9]{1,3}$ ]] && ((10#$volume <= 100)) || { echo 'Volume must be 0-100' >&2; exit 1; }
((10#$volume != 0)) || exit 0
if [[ "$device" == default && "$volume" == 100 ]]; then
    exec bash "$core_dir/../vendor/robotspeak/speak.sh" \
        -Word "$word" -Mood "$mood" -Callsign "$callsign" -PauseMs 0
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Export with Perl, including in WSL: selecting a Windows output must not
# require slow PowerShell synthesis or depend on the Linux default sink.
perl "$core_dir/../vendor/robotspeak/robot-voice.pl" \
    -Word "$word" -Mood "$mood" -Callsign "$callsign" -OutFile "$work/phrase.wav"
perl "$core_dir/volume.pl" "$work/phrase.wav" "$volume"
perl "$core_dir/audio.pl" play "$device" "$work/phrase.wav"
