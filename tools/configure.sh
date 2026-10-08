#!/usr/bin/env bash
# Inspect or change RobotSpeak's own preferences. Never changes system defaults.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "${1:-show}" in
    show|events|volume|parts|on|off)
        exec perl "$repo_dir/core/settings.pl" "${@:-show}" ;;
    devices)
        exec perl "$repo_dir/core/audio.pl" list ;;
    select)
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT
        perl "$repo_dir/core/audio.pl" list > "$work/devices.json"
        perl -MJSON::PP -0777 -ne '
            my $devices=decode_json($_); binmode STDOUT, ":utf8";
            print "0) System default\n";
            for my $i (0..$#$devices) { print($i+1, ") ", $devices->[$i]{name}, "\n"); }
        ' "$work/devices.json"
        read -r -p 'Output number: ' choice
        device="$(RS_CHOICE="$choice" perl -MJSON::PP -0777 -ne '
            my $devices=decode_json($_); my $choice=$ENV{RS_CHOICE};
            die "Invalid output number\n" unless $choice =~ /^\d+$/ && $choice <= @$devices;
            binmode STDOUT, ":utf8"; print $choice == 0 ? "default" : $devices->[$choice-1]{id};
        ' "$work/devices.json")"
        perl "$repo_dir/core/settings.pl" device "$device" ;;
    device)
        [[ $# == 2 ]] || { echo 'Usage: device <identifier|default>' >&2; exit 1; }
        if [[ "$2" != default ]]; then
            perl "$repo_dir/core/audio.pl" list | RS_DEVICE="$2" perl -MJSON::PP -MEncode=decode,FB_CROAK -0777 -ne '
                my $devices = decode_json($_);
                my $device = decode("UTF-8", $ENV{RS_DEVICE}, FB_CROAK);
                die "Audio device not available\n" unless grep { $_->{id} eq $device } @$devices;
            '
        fi
        exec perl "$repo_dir/core/settings.pl" device "$2" ;;
    test)
        # Bypass the event filter for this explicit listening test, keeping routing.
        settings="$(perl "$repo_dir/core/settings.pl" effective)"
        { IFS= read -r events; IFS= read -r device; IFS= read -r volume; IFS= read -r enabled; IFS= read -r parts; } <<< "$settings"
        case "${2:-done}" in
            received) word=RCV mood=Neutral ;;
            done) word=OK mood=Satisfied ;;
            review) word=OK mood=Doubtful ;;
            question) word=K mood=Curious ;;
            approval) word=K mood=Concerned ;;
            failed) word=ERR mood=Apologetic ;;
            blocked) word=ERR mood=Concerned ;;
            turn) word=K mood=Neutral ;;
            *) echo 'Unknown RobotSpeak state' >&2; exit 1 ;;
        esac
        exec bash "$repo_dir/core/play.sh" "$word" "$mood" "${ROBOTSPEAK_CALLSIGN:-2}" "$device" "$volume" "$parts" ;;
    *) echo 'Usage: configure.sh on|off|volume <0-100>|parts <all|callsign+word+mood>|show|devices|select|device <id>|events <all|none|keys>|test [key]' >&2; exit 1 ;;
esac
