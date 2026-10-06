#!/usr/bin/env bash
# Claude Code hook: maps each event to a dictionary phrase.
# Claude Code speaks with callsign 1 unless ROBOTSPEAK_CALLSIGN says otherwise.
set -u
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
input="$(cat)"
field() {
    printf "%s" "$input" | RS_FIELD="$1" perl -MJSON::PP -0777 -ne '
        my $value = eval { decode_json($_)->{$ENV{RS_FIELD}} } // "";
        binmode STDOUT, ":utf8"; print $value;
    '
}
say() { bash "$repo_dir/core/say.sh" "$1" "${ROBOTSPEAK_CALLSIGN:-1}"; }

case "$(field hook_event_name)" in
    SessionStart)
        perl -MJSON::PP -Ci -0777 -ne '
            print JSON::PP->new->utf8->encode({hookSpecificOutput => {
                hookEventName => "SessionStart", additionalContext => $_ }});
        ' "$repo_dir/core/instructions.md" ;;
    UserPromptSubmit)
        source="$(field source)"
        if [[ "${ROBOTSPEAK_RECEIVED:-1}" == 1 && ( -z "$source" || "$source" == user ) ]]; then
            say received
        fi ;;
    Stop)              say "$(field last_assistant_message | bash "$repo_dir/core/marker.sh")" ;;
    StopFailure)       say blocked ;;
    PermissionRequest) say approval ;;
    PreToolUse)        say question ;;
    Notification)      [[ "$(field notification_type)" == elicitation_dialog ]] && say question ;;
esac
exit 0
