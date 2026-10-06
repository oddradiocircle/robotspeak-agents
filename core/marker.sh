#!/usr/bin/env bash
# Reads a message on stdin and prints the key of its RobotSpeak marker.
# The marker counts only as the last non-empty line; otherwise the key is turn.
set -u
last="$(tr -d '\r' | awk 'NF { line = $0 } END { print line }')"
last="${last#"${last%%[![:space:]]*}"}"
last="${last%"${last##*[![:space:]]}"}"
if [[ "$last" =~ ^\[\[rs:(received|done|review|question|approval|failed|blocked|turn)\]\]$ ]]; then
    echo "${BASH_REMATCH[1]}"
else
    echo turn
fi
