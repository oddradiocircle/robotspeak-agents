#!/usr/bin/env perl
# Scale only RobotSpeak PCM samples; never changes a system or device mixer.
use strict;
use warnings;
my ($file, $volume) = @ARGV;
die "Usage: volume.pl <RobotSpeak WAV> <0-100>\n" unless @ARGV == 2 &&
    $volume =~ /^\d{1,3}\z/ && $volume <= 100;
open my $fh, '<:raw', $file or die "$file: $!\n";
local $/; my $wav = <$fh>;
close $fh or die "$file: $!\n";
die "Invalid RobotSpeak PCM file\n" unless length($wav) >= 44 &&
    substr($wav, 0, 4) eq 'RIFF' && substr($wav, 8, 8) eq 'WAVEfmt ' &&
    unpack('V', substr($wav, 16, 4)) == 16 && unpack('v', substr($wav, 20, 2)) == 1 &&
    unpack('v', substr($wav, 22, 2)) == 1 && unpack('V', substr($wav, 24, 4)) == 22050 &&
    unpack('v', substr($wav, 34, 2)) == 16 && substr($wav, 36, 4) eq 'data' &&
    unpack('V', substr($wav, 40, 4)) == length($wav) - 44 && (length($wav) - 44) % 2 == 0;
exit 0 if $volume == 100;
my @pcm = map { int($_ * $volume / 100) } unpack('s<*', substr($wav, 44));
open $fh, '>:raw', $file or die "$file: $!\n";
print {$fh} substr($wav, 0, 44), pack('s<*', @pcm) or die "$file: $!\n";
close $fh or die "$file: $!\n";
