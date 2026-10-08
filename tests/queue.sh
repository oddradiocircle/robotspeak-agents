#!/usr/bin/env bash
# Off cancels a queued phrase; on permits playback again. Fake player, no audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/runtime"
export ROBOTSPEAK_CONFIG="$work/config.json" XDG_RUNTIME_DIR="$work/runtime"
export ROBOTSPEAK_ENGINE=perl ROBOTSPEAK_MUTE=0 RS_PLAYFILE="$work/played.wav"
unset ROBOTSPEAK_DEVICE ROBOTSPEAK_VOLUME ROBOTSPEAK_EVENTS ROBOTSPEAK_DEBUG
cat > "$work/bin/paplay" <<'PLAYER'
#!/usr/bin/env bash
cp "${@: -1}" "$RS_PLAYFILE"
PLAYER
chmod +x "$work/bin/paplay"
export PATH="$work/bin:$PATH"
perl "$repo_dir/core/settings.pl" device pulse:test >/dev/null
# Occupy the shared lock until off has been saved. A bounded holder avoids hangs.
perl -MFcntl=:flock -e '
    my ($lock,$ready,$release)=@ARGV;
    open my $fh, ">>", $lock or die $!; flock($fh, LOCK_EX) or die $!;
    open my $mark, ">", $ready or die $!; close $mark;
    my $until=time+5;
    while (!-e $release && time<$until) { select undef,undef,undef,0.01; }
' "$work/runtime/robotspeak-agents.lock" "$work/ready" "$work/release" &
holder=$!
wait_for() {
    local attempts=0
    until [[ -e "$1" ]]; do
        ((attempts+=1))
        ((attempts <= 250)) || { echo "Timed out waiting for $1" >&2; exit 1; }
        sleep 0.02
    done
}
wait_for "$work/ready"
(
    set -- done 2
    source "$repo_dir/core/say.sh"
    touch "$work/queued"
    wait "$!"
) &
queued=$!
wait_for "$work/queued"
perl "$repo_dir/core/settings.pl" off >/dev/null
touch "$work/release"
wait "$holder"
wait "$queued"
[[ ! -e "$RS_PLAYFILE" ]] || { echo 'Off did not cancel queued audio'; exit 1; }
perl "$repo_dir/core/settings.pl" on >/dev/null
(
    set -- done 2
    source "$repo_dir/core/say.sh"
    wait "$!"
)
[[ -s "$RS_PLAYFILE" ]] || { echo 'On did not restore playback'; exit 1; }
echo 'Queue and shared switch: all checks passed'
