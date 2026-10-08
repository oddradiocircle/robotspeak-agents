#!/usr/bin/env bash
# Preferences, event filtering, and argument-safe routing. No actual audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export ROBOTSPEAK_CONFIG="$work/preferences.json" ROBOTSPEAK_MUTE=1 ROBOTSPEAK_DEBUG=1
unset ROBOTSPEAK_EVENTS ROBOTSPEAK_DEVICE ROBOTSPEAK_RECEIVED ROBOTSPEAK_VOLUME ROBOTSPEAK_PARTS
[[ "$(perl "$repo_dir/core/settings.pl" effective)" == $'approval,blocked,done,failed,question,received,review,turn\ndefault\n50\n1\ncallsign+word+mood' ]]
perl "$repo_dir/core/settings.pl" events review,question,approval,blocked >/dev/null
[[ -z "$(bash "$repo_dir/core/say.sh" done 2 2>&1)" ]]
[[ "$(bash "$repo_dir/core/say.sh" question 2 2>&1)" == 'question K Curious 2' ]]
[[ "$(ROBOTSPEAK_EVENTS=all bash "$repo_dir/core/say.sh" done 2 2>&1)" == 'done OK Satisfied 2' ]]
[[ -z "$(ROBOTSPEAK_EVENTS=none bash "$repo_dir/core/say.sh" question 2 2>&1)" ]]
before="$(cat "$ROBOTSPEAK_CONFIG")"
if perl "$repo_dir/core/settings.pl" events done,unknown >/dev/null 2>&1; then echo 'Invalid event accepted'; exit 1; fi
[[ "$(cat "$ROBOTSPEAK_CONFIG")" == "$before" ]]
perl "$repo_dir/core/settings.pl" device 'pulse:speaker with spaces' >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective)" == $'review,question,approval,blocked\npulse:speaker with spaces\n50\n1\ncallsign+word+mood' ]]
[[ "$(ROBOTSPEAK_DEVICE=default perl "$repo_dir/core/settings.pl" effective)" == $'review,question,approval,blocked\ndefault\n50\n1\ncallsign+word+mood' ]]
if ROBOTSPEAK_DEVICE=$'pulse:name\ninjected' perl "$repo_dir/core/settings.pl" effective >/dev/null 2>&1; then echo 'Invalid device accepted'; exit 1; fi
perl "$repo_dir/core/settings.pl" events none >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective)" == $'\npulse:speaker with spaces\n50\n1\ncallsign+word+mood' ]]
perl "$repo_dir/core/settings.pl" device 'pulse:altavoces-café' >/dev/null
[[ "$(perl "$repo_dir/core/settings.pl" effective)" == $'\npulse:altavoces-café\n50\n1\ncallsign+word+mood' ]]
[[ "$(ROBOTSPEAK_DEVICE='macos:salida-música' perl "$repo_dir/core/settings.pl" effective)" == $'\nmacos:salida-música\n50\n1\ncallsign+word+mood' ]]
# Both adapters share the switch; on restores the event, output and volume choices.
bash "$repo_dir/tools/configure.sh" events all >/dev/null
bash "$repo_dir/skills/robotspeak/scripts/configure.sh" volume 25 >/dev/null
[[ "$(ROBOTSPEAK_VOLUME=75 perl "$repo_dir/core/settings.pl" effective)" == $'approval,blocked,done,failed,question,received,review,turn\npulse:altavoces-café\n75\n1\ncallsign+word+mood' ]]
before="$(cat "$ROBOTSPEAK_CONFIG")"
for bad in -1 101 1.5 junk ''; do
    if bash "$repo_dir/tools/configure.sh" volume "$bad" >/dev/null 2>&1; then echo 'Invalid volume accepted'; exit 1; fi
    if ROBOTSPEAK_VOLUME="$bad" perl "$repo_dir/core/settings.pl" effective >/dev/null 2>&1; then echo 'Invalid volume override accepted'; exit 1; fi
    [[ "$(cat "$ROBOTSPEAK_CONFIG")" == "$before" ]]
done
# Parts accept the engines' spelling and are stored in one canonical order.
effective_parts() { perl "$repo_dir/core/settings.pl" effective | sed -n 5p; }
bash "$repo_dir/tools/configure.sh" parts MSG,MOOD >/dev/null
[[ "$(effective_parts)" == word+mood ]]
bash "$repo_dir/tools/configure.sh" parts 'mood+ID+word' >/dev/null
[[ "$(effective_parts)" == callsign+word+mood ]]
[[ "$(ROBOTSPEAK_PARTS=Mood effective_parts)" == mood ]]
[[ "$(ROBOTSPEAK_PARTS=all effective_parts)" == callsign+word+mood ]]
bash "$repo_dir/tools/configure.sh" parts callsign+mood >/dev/null
parts_before="$(cat "$ROBOTSPEAK_CONFIG")"
for bad in '' voice word+ 'word mood' +mood; do
    if bash "$repo_dir/tools/configure.sh" parts "$bad" >/dev/null 2>&1; then echo "Invalid parts accepted: $bad"; exit 1; fi
    if ROBOTSPEAK_PARTS="$bad" perl "$repo_dir/core/settings.pl" effective >/dev/null 2>&1; then echo "Invalid parts override accepted: $bad"; exit 1; fi
    [[ "$(cat "$ROBOTSPEAK_CONFIG")" == "$parts_before" ]]
done
bash "$repo_dir/tools/configure.sh" parts all >/dev/null
[[ "$(cat "$ROBOTSPEAK_CONFIG")" == "$before" ]]
bash "$repo_dir/skills/robotspeak/scripts/configure.sh" off >/dev/null
for adapter in claude-code codex; do
    [[ -z "$(printf '%s' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}' | bash "$repo_dir/adapters/$adapter/hook.sh" 2>&1 >/dev/null)" ]]
done
bash "$repo_dir/skills/robotspeak/scripts/configure.sh" on >/dev/null
[[ "$(cat "$ROBOTSPEAK_CONFIG")" == "$before" ]]
[[ "$(printf '%s' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}' | bash "$repo_dir/adapters/claude-code/hook.sh" 2>&1 >/dev/null)" == 'done OK Satisfied 1' ]]
[[ "$(printf '%s' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}' | bash "$repo_dir/adapters/codex/hook.sh" 2>&1 >/dev/null)" == 'done OK Satisfied 2' ]]
[[ -z "$(ROBOTSPEAK_VOLUME=0 bash "$repo_dir/core/say.sh" done 2 2>&1)" ]]
printf 'not JSON' > "$ROBOTSPEAK_CONFIG"
if perl "$repo_dir/core/settings.pl" effective >/dev/null 2>&1; then echo 'Malformed settings accepted'; exit 1; fi
# Every player receives the chosen device and path as literal arguments.
mkdir "$work/bin"
for player in paplay pw-play aplay; do
    cat > "$work/bin/$player" <<'PLAYER'
#!/usr/bin/env perl
use JSON::PP;
open my $fh, '>:raw', $ENV{RS_TEST_ARGS} or die $!;
print {$fh} encode_json(\@ARGV);
PLAYER
    chmod +x "$work/bin/$player"
done
export PATH="$work/bin:$PATH" RS_TEST_ARGS="$work/args.json"
for backend in pulse pipewire alsa; do
    perl "$repo_dir/core/audio.pl" play "$backend:speaker with spaces" "$work/a file.wav"
    RS_TEST_BACKEND="$backend" perl -MJSON::PP -e '
        local $/; open my $fh, "<", $ENV{RS_TEST_ARGS} or die $!;
        my $args=decode_json(<$fh>);
        die "Split device or filename" unless $args->[-1] eq "$ARGV[0]/a file.wav";
        my $backend=$ENV{RS_TEST_BACKEND};
        die "Missing Pulse target" if $backend eq "pulse" && $args->[0] ne "--device=speaker with spaces";
        die "Missing PipeWire target" if $backend eq "pipewire" && $args->[0] ne "--target=speaker with spaces";
        die "Missing ALSA target" if $backend eq "alsa" && $args->[2] ne "speaker with spaces";
    ' "$work"
done
# An unavailable target must fail; it must not retry the default device.
cat > "$work/bin/paplay" <<'PLAYER'
#!/usr/bin/env bash
exit 1
PLAYER
if perl "$repo_dir/core/audio.pl" play pulse:missing "$work/a.wav" >/dev/null 2>&1; then echo 'Unavailable device accepted'; exit 1; fi
echo 'Settings and routing: all checks passed'
