#!/usr/bin/env bash
# Claude Desktop MCP server over stdio, with a recording say.sh. No audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/tree/adapters/claude-desktop" "$work/tree/core"
cp "$repo_dir/adapters/claude-desktop/server.js" "$repo_dir/adapters/claude-desktop/manifest.json" "$work/tree/adapters/claude-desktop/"
cat > "$work/tree/core/say.sh" <<'SAY'
#!/usr/bin/env bash
echo "$*" >> "$RS_TEST_LOG"
SAY
unset ROBOTSPEAK_CALLSIGN
export RS_TEST_LOG="$work/said.log"
: > "$RS_TEST_LOG"
run() {
    printf '%s\n' "$@" | node "$work/tree/adapters/claude-desktop/server.js" > "$work/replies.jsonl"
    sleep 0.3
}
run '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"robotspeak_say","arguments":{"state":"done"}}}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"robotspeak_say","arguments":{"state":"received"}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"other","arguments":{}}}' \
    '{"jsonrpc":"2.0","id":6,"method":"resources/list"}' \
    'not json' \
    '{"jsonrpc":"2.0","id":7,"method":"ping"}'
RS_VERSION="$(perl -MJSON::PP -0777 -ne 'print decode_json($_)->{version}' "$repo_dir/adapters/claude-desktop/manifest.json")" \
perl -MJSON::PP -e '
    open my $fh, "<", $ARGV[0] or die $!;
    my %reply; my @errors;
    while (<$fh>) { my $r = decode_json($_); push @errors, $r if !defined $r->{id}; $reply{$r->{id}} = $r if defined $r->{id}; }
    my $init = $reply{1}{result};
    die "initialize" unless $init->{protocolVersion} eq "2025-06-18" && $init->{serverInfo}{version} eq $ENV{RS_VERSION}
        && $init->{capabilities}{tools} && $init->{instructions} =~ /robotspeak_say/;
    my ($tool) = @{$reply{2}{result}{tools}};
    die "tools/list" unless $tool->{name} eq "robotspeak_say" && join(",", @{$tool->{inputSchema}{properties}{state}{enum}}) eq "done,review,question,failed,blocked,turn";
    die "call" unless $reply{3}{result}{content}[0]{text} eq "Anunciado: done" && !$reply{3}{result}{isError};
    die "bad state" unless $reply{4}{result}{isError};
    die "unknown tool" unless $reply{5}{error}{code} == -32602;
    die "unknown method" unless $reply{6}{error}{code} == -32601;
    die "parse error" unless @errors == 1 && $errors[0]{error}{code} == -32700;
    die "ping" unless ref $reply{7}{result} eq "HASH";
    die "notification answered" if keys %reply != 7;
' "$work/replies.jsonl"
[[ "$(cat "$RS_TEST_LOG")" == 'done 1' ]] || { echo "Unexpected phrases: $(cat "$RS_TEST_LOG")"; exit 1; }
: > "$RS_TEST_LOG"
ROBOTSPEAK_CALLSIGN=Common run '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"robotspeak_say","arguments":{"state":"question"}}}'
ROBOTSPEAK_CALLSIGN='$(bad)' run '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"robotspeak_say","arguments":{"state":"blocked"}}}'
[[ "$(cat "$RS_TEST_LOG")" == $'question Common\nblocked 1' ]] || { echo "Callsign: $(cat "$RS_TEST_LOG")"; exit 1; }
echo 'Claude Desktop MCP server: all checks passed'
