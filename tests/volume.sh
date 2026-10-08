#!/usr/bin/env bash
# Volume changes PCM amplitude, preserving timings and the original 100% audio.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
perl - "$repo_dir" "$work" <<'PERL'
use strict; use warnings;
my ($root, $work) = @ARGV;
my @samples = (-32768, -32767, -3, -1, 0, 1, 3, 32767);
my $source = pack('a4 V a8 V v v V V v v a4 V s<*', 'RIFF', 52, 'WAVEfmt ', 16, 1, 1, 22050, 44100, 2, 16, 'data', 16, @samples);
my %expected = (
    0 => [(0) x 8],
    25 => [-8192, -8191, 0, 0, 0, 0, 0, 8191],
    50 => [-16384, -16383, -1, 0, 0, 0, 1, 16383],
    100 => \@samples,
);
for my $volume (sort {$a <=> $b} keys %expected) {
    my $file = "$work/$volume.wav";
    open my $fh, '>:raw', $file or die $!; print {$fh} $source; close $fh;
    system($^X, "$root/core/volume.pl", $file, $volume) == 0 or die "Volume command failed";
    open $fh, '<:raw', $file or die $!; local $/; my $scaled = <$fh>; close $fh;
    die "Header or duration changed" unless length($scaled) == length($source) && substr($scaled, 0, 44) eq substr($source, 0, 44);
    my @actual = unpack('s<*', substr($scaled, 44));
    die "Incorrect $volume% samples" unless "@actual" eq "@{$expected{$volume}}";
}
PERL
for bad in -1 101 1.5 junk ''; do
    if perl "$repo_dir/core/volume.pl" "$work/100.wav" "$bad" >/dev/null 2>&1; then echo 'Invalid volume accepted'; exit 1; fi
done
[[ "$(ROBOTSPEAK_ENGINE=perl bash "$repo_dir/core/play.sh" OK Satisfied 2 default 0 2>&1)" == '' ]]
echo 'PCM volume: all checks passed'
