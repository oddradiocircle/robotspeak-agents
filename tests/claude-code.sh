#!/usr/bin/env bash
# Checks the Claude Code adapter without sound: every event must map to the
# expected phrase and callsign, and the session must receive the instructions.
set -u
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ROBOTSPEAK_MUTE=1 ROBOTSPEAK_DEBUG=1
unset ROBOTSPEAK_CALLSIGN ROBOTSPEAK_RECEIVED
failures=0
check() {
    local expected="$1" json="$2" actual
    actual="$(printf '%s' "$json" | bash "$repo_dir/adapters/claude-code/hook.sh" 2>&1 >/dev/null)"
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $json -> '$actual', expected '$expected'"
        failures=$((failures + 1))
    fi
}
check 'received RCV Neutral 1'  '{"hook_event_name":"UserPromptSubmit","prompt":"hola","source":"user"}'
check 'received RCV Neutral 1'  '{"hook_event_name":"UserPromptSubmit","prompt":"hola"}'
check ''                        '{"hook_event_name":"UserPromptSubmit","prompt":"x","source":"loop_wakeup"}'
check 'done OK Satisfied 1'     '{"hook_event_name":"Stop","last_assistant_message":"Listo.\n\n[[rs:done]]\n"}'
check 'review OK Doubtful 1'    '{"hook_event_name":"Stop","last_assistant_message":"Revisa ñ.\r\n  [[rs:review]]  "}'
check 'question K Curious 1'    '{"hook_event_name":"Stop","last_assistant_message":"¿Sigo?\n[[rs:question]]"}'
check 'failed ERR Apologetic 1' '{"hook_event_name":"Stop","last_assistant_message":"No existe.\n[[rs:failed]]"}'
check 'blocked ERR Concerned 1' '{"hook_event_name":"Stop","last_assistant_message":"Falta la clave.\n[[rs:blocked]]"}'
check 'turn K Neutral 1'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]\nDespués de la marca."}'
check 'turn K Neutral 1'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:DONE]]"}'
check 'turn K Neutral 1'        '{"hook_event_name":"Stop","last_assistant_message":"[[rs:bogus]]"}'
check 'turn K Neutral 1'        '{"hook_event_name":"Stop"}'
check 'blocked ERR Concerned 1' '{"hook_event_name":"StopFailure","error":"rate_limit"}'
check 'approval K Concerned 1'  '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
check 'question K Curious 1'    '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}'
check 'question K Curious 1'    '{"hook_event_name":"Notification","notification_type":"elicitation_dialog","message":"m"}'
check ''                        '{"hook_event_name":"Notification","notification_type":"permission_prompt","message":"m"}'
check ''                        'esto no es JSON'
ROBOTSPEAK_CALLSIGN=3 check 'done OK Satisfied 3' '{"hook_event_name":"Stop","last_assistant_message":"[[rs:done]]"}'
ROBOTSPEAK_RECEIVED=0 check '' '{"hook_event_name":"UserPromptSubmit","prompt":"hola","source":"user"}'

context="$(printf '%s' '{"hook_event_name":"SessionStart","source":"startup"}' \
    | bash "$repo_dir/adapters/claude-code/hook.sh" 2>/dev/null \
    | perl -MJSON::PP -CO -0777 -ne 'print decode_json($_)->{hookSpecificOutput}{additionalContext}')"
if [[ "$context" != *'[[rs:<clave>]]'* || "$context" != *'última línea'* ]]; then
    echo 'FAIL: SessionStart did not return the instructions'
    failures=$((failures + 1))
fi

if ((failures)); then echo "$failures failure(s)"; exit 1; fi
echo 'Claude Code adapter: all checks passed'
