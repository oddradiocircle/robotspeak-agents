#!/usr/bin/env bash
# Reads a message on stdin and prints the key of its RobotSpeak marker.
# The marker counts only as the last non-empty line, outside Markdown code.
set -u
perl -ne '
    s/\r?\n\z//;
    next unless /\S/;
    $last = $_;
    $last_in_code = defined($fence) || /^(?: {4}| {0,3}\t)/;
    if (defined $fence) {
        $fence = undef if /^ {0,3}\Q$fence\E[\Q$fence_char\E]*[ \t]*$/;
    } elsif (/^ {0,3}(`{3,}|~{3,})(.*)$/) {
        my ($delimiter, $info) = ($1, $2);
        if (substr($delimiter, 0, 1) ne "`" || $info !~ /`/) {
            $fence = $delimiter;
            $fence_char = substr($fence, 0, 1);
            $last_in_code = 1;
        }
    }
    END {
        my $key = !$last_in_code && defined($last) &&
            $last =~ /^[ \t]*\[\[rs:(received|done|review|question|approval|failed|blocked|turn)\]\][ \t]*$/
            ? $1 : "turn";
        print "$key\n";
    }
'
