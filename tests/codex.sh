#!/usr/bin/env bash
# Checks the Codex adapter without sound: every event must map to the
# expected phrase and callsign, and the session must receive the instructions.
set -u
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ROBOTSPEAK_MUTE=1 ROBOTSPEAK_DEBUG=1 ROBOTSPEAK_EVENTS=all ROBOTSPEAK_DEVICE=default
export ROBOTSPEAK_CONFIG=/dev/null/robotspeak-test.json
unset ROBOTSPEAK_CALLSIGN ROBOTSPEAK_RECEIVED
failures=0
check() {
    local expected="$1" json="$2" actual
    actual="$(printf '%s' "$json" | bash "$repo_dir/adapters/codex/hook.sh" 2>&1 >/dev/null)"
    if [[ $? != 0 ]]; then
        echo "FAIL: hook exited unsuccessfully: $json"
        failures=$((failures + 1))
    fi
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $json -> '$actual', expected '$expected'"
        failures=$((failures + 1))
    fi
}
check 'received RCV Neutral 2'  '{"hook_event_name":"UserPromptSubmit","prompt":"hola","source":"user"}'
check 'received RCV Neutral 2'  '{"hook_event_name":"UserPromptSubmit","prompt":"hola"}'
check 'done OK Satisfied 2'     '{"hook_event_name":"Stop","last_assistant_message":"Listo.\n\n[[rs:done]]\n"}'
check 'review OK Doubtful 2'    '{"hook_event_name":"Stop","last_assistant_message":"Revisa ñ.\r\n  [[rs:review]]  "}'
check 'question K Curious 2'    '{"hook_event_name":"Stop","last_assistant_message":"¿Sigo?\n[[rs:question]]"}'
check 'failed ERR Apologetic 2' '{"hook_event_name":"Stop","last_assistant_message":"No existe.\n[[rs:failed]]"}'
check 'blocked ERR Concerned 2' '{"hook_event_name":"Stop","last_assistant_message":"Falta la clave.\n[[rs:blocked]]"}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]\nDespués de la marca."}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:DONE]]"}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:bogus]]"}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop"}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop","last_assistant_message":null}'
check 'turn K Neutral 2'        '{"hook_event_name":"Stop","last_assistant_message":["[[rs:done]]"]}'
check '' '{"hook_event_name":"StopFailure"}'
check 'approval K Concerned 2'  '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
check 'question K Curious 2'    '{"hook_event_name":"PreToolUse","tool_name":"request_user_input"}'
check 'question K Curious 2' '{"hook_event_name":"PreToolUse","tool_name":"request_user_input_async"}'
check '' '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
check '' '{"hook_event_name":"SubagentStop","last_assistant_message":"[[rs:done]]"}'
check ''                        '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"m"}'
check ''                        'esto no es JSON'
ROBOTSPEAK_CALLSIGN=3 check 'done OK Satisfied 3' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}'
ROBOTSPEAK_RECEIVED=0 check '' '{"hook_event_name":"UserPromptSubmit","prompt":"hola","source":"user"}'

context="$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash "$repo_dir/adapters/codex/hook.sh" 2>/dev/null \
    | perl -MJSON::PP -CO -0777 -ne 'print decode_json($_)->{hookSpecificOutput}{additionalContext}')"
if [[ "$context" != "$(cat "$repo_dir/core/instructions.md")" ]]; then
    echo 'FAIL: SessionStart did not return the instructions'
    failures=$((failures + 1))
fi

if ((failures)); then echo "$failures failure(s)"; exit 1; fi
# Codex requires valid JSON for Stop and must receive no approval decision.
stop="$(printf '%s' '{"hook_event_name":"Stop"}' | bash "$repo_dir/adapters/codex/hook.sh" 2>/dev/null)"
[[ "$stop" == '{}' ]] || { echo 'FAIL: invalid Stop output'; exit 1; }
permission="$(printf '%s' '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}' | bash "$repo_dir/adapters/codex/hook.sh" 2>/dev/null)"
[[ -z "$permission" ]] || { echo 'FAIL: permission notification returned a decision'; exit 1; }
# Check the manifest and invoke the actual configured commands, with a root
# containing spaces to catch quoting errors in plugin installation paths.
perl -MJSON::PP -e '
    my $root = shift;
    sub read_json { local $/; open my $fh, "<", shift or die $!; decode_json(<$fh>) }
    my $manifest = read_json("$root/.codex-plugin/plugin.json");
    my $config = read_json("$root/" . $manifest->{hooks});
    die "Unexpected hooks" unless keys(%{$config->{hooks}}) == 5;
    for my $event (keys %{$config->{hooks}}) {
        for my $group (@{$config->{hooks}{$event}}) {
            for my $hook (@{$group->{hooks}}) {
                die "Non-command hook" unless $hook->{type} eq "command";
                die "Wrong adapter" unless $hook->{command} =~ m{adapters/codex/hook[.]sh};
            }
        }
    }
' "$repo_dir" || exit 1
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ln -s "$repo_dir" "$work/plugin with spaces"
export PLUGIN_ROOT="$work/plugin with spaces"
command="$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{hooks}{Stop}[0]{hooks}[0]{command}' "$repo_dir/adapters/codex/hooks.json")"
output="$(printf '%s' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}' | bash -c "$command" 2>&1)"
[[ "$output" == $'done OK Satisfied 2\n{}' ]] || { echo "FAIL: configured command: $output"; exit 1; }
echo 'Codex adapter: all checks passed'
