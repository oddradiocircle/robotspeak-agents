#!/usr/bin/env bash
# Literal examples and Markdown code must never announce success.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
check() {
    local expected="$1" message="$2" actual
    actual="$(printf '%s' "$message" | bash "$repo_dir/core/marker.sh")"
    [[ "$actual" == "$expected" ]] || {
        printf 'FAIL: marker returned %s, expected %s\n' "$actual" "$expected"
        exit 1
    }
}
check done $'Listo.\r\n\r\n  [[rs:done]]  \r\n\r\n'
check turn ''
check turn '[[rs:DONE]]'
check turn '[[rs:unknown]]'
check turn $'[[rs:done]]\nQueda pendiente.'
check turn $'```text\n[[rs:done]]'
check turn $'~~~text\n[[rs:done]]'
check turn $'````text\n```\n[[rs:done]]'
check turn $'```text\n~~~\n[[rs:done]]'
check turn $'```text\n[[rs:done]]\n```'
check turn '    [[rs:done]]'
check turn $'\t[[rs:done]]'
check turn $'  \t[[rs:done]]'
check turn '> [[rs:done]]'
check done $'```text\nEjemplo.\n```\n[[rs:done]]'
check done $'~~~text\nEjemplo.\n~~~~\n[[rs:done]]'
check review $'[[rs:done]]\n[[rs:review]]'
echo 'Marker parser: all checks passed'
