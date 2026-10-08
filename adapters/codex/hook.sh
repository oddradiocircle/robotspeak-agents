#!/usr/bin/env bash
# Codex lifecycle hooks. Never return an approval or continuation decision.
set -u
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
input="$(cat)"
field() {
    printf '%s' "$input" | RS_FIELD="$1" perl -MJSON::PP -0777 -ne '
        my $value = eval { decode_json($_)->{$ENV{RS_FIELD}} } // "";
        binmode STDOUT, ":utf8"; print $value unless ref $value;
    '
}
say() { bash "$repo_dir/core/say.sh" "$1" "${ROBOTSPEAK_CALLSIGN:-2}"; }
case "$(field hook_event_name)" in
    SessionStart)
        perl -MJSON::PP -Ci -0777 -ne '
            print JSON::PP->new->utf8->encode({hookSpecificOutput => {
                hookEventName => "SessionStart", additionalContext => $_ }});
        ' "$repo_dir/core/instructions.md" ;;
    UserPromptSubmit)
        if [[ "${ROBOTSPEAK_RECEIVED:-1}" == 1 ]]; then say received; fi ;;
    Stop)
        say "$(field last_assistant_message | bash "$repo_dir/core/marker.sh")"
        printf '{}\n' ;;
    PermissionRequest) say approval ;;
    PreToolUse)
        case "$(field tool_name)" in
            request_user_input|request_user_input_async) say question ;;
        esac ;;
esac
exit 0
