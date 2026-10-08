#!/usr/bin/env perl
# Shared user preferences. JSON is data, never evaluated as shell input.
use strict;
use warnings;
use JSON::PP;
use File::Spec;
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Encode qw(decode FB_CROAK);
@ARGV = map { decode('UTF-8', $_, FB_CROAK) } @ARGV;
binmode STDOUT, ':encoding(UTF-8)';
my %keys = map { $_ => 1 } qw(received done review question approval failed blocked turn);
my $home = $ENV{XDG_CONFIG_HOME} // File::Spec->catdir($ENV{HOME}, '.config');
my $path = $ENV{ROBOTSPEAK_CONFIG} // File::Spec->catfile($home, 'robotspeak-agents', 'config.json');
my $config = { events => [sort keys %keys], device => 'default', volume => 50, enabled => JSON::PP::true };
if (-e $path) {
    open my $fh, '<:raw', $path or die "$path: $!\n";
    local $/;
    my $loaded = eval { decode_json(<$fh>) };
    die "Invalid RobotSpeak configuration: $path\n" unless ref($loaded) eq 'HASH';
    $config = { %$config, %$loaded };
}
sub validate {
    my ($value) = @_;
    die "events must be a list of RobotSpeak states\n" unless ref($value->{events}) eq 'ARRAY';
    for (@{$value->{events}}) { die "Unknown RobotSpeak state\n" if ref($_) || !$keys{$_ // ''}; }
    die "Invalid audio device identifier\n" if !defined($value->{device}) || ref($value->{device}) ||
        $value->{device} =~ /[\x00-\x1f]/ || $value->{device} !~ /^(?:default|(?:windows|macos|pulse|pipewire|alsa):.+)\z/;
    die "Volume must be an integer from 0 to 100\n" if !defined($value->{volume}) || ref($value->{volume}) ||
        $value->{volume} !~ /^\d{1,3}\z/ || $value->{volume} > 100;
    die "enabled must be a boolean\n" unless JSON::PP::is_bool($value->{enabled});
}
validate($config);
my $action = shift(@ARGV) // 'show';
if ($action eq 'effective') {
    if (exists $ENV{ROBOTSPEAK_EVENTS}) {
        my $events = $ENV{ROBOTSPEAK_EVENTS};
        $config->{events} = $events eq 'all' ? [sort keys %keys] : $events eq 'none' || $events eq '' ? [] : [split /,/, $events, -1];
    }
    $config->{device} = decode('UTF-8', $ENV{ROBOTSPEAK_DEVICE}, FB_CROAK) if exists $ENV{ROBOTSPEAK_DEVICE};
    $config->{volume} = $ENV{ROBOTSPEAK_VOLUME} if exists $ENV{ROBOTSPEAK_VOLUME};
    validate($config);
    print join(',', @{$config->{events}}), "\n", $config->{device}, "\n", 0 + $config->{volume}, "\n", $config->{enabled} ? "1\n" : "0\n";
} elsif ($action eq 'show') {
    print JSON::PP->new->pretty->canonical->encode($config);
} elsif ($action =~ /^(?:events|device|volume|on|off)\z/) {
    if ($action eq 'events') {
        die "Usage: events all|none|state,state\n" unless @ARGV == 1;
        my $events = $ARGV[0];
        $config->{events} = $events eq 'all' ? [sort keys %keys] : $events eq 'none' ? [] : [split /,/, $events, -1];
    } elsif ($action eq 'device') {
        die "Usage: device <identifier>\n" unless @ARGV == 1;
        $config->{device} = $ARGV[0];
    } elsif ($action eq 'volume') {
        die "Usage: volume <0-100>\n" unless @ARGV == 1;
        $config->{volume} = $ARGV[0];
    } else {
        die "Usage: $action\n" if @ARGV;
        $config->{enabled} = $action eq 'on' ? JSON::PP::true : JSON::PP::false;
    }
    validate($config);
    $config->{volume} = 0 + $config->{volume};
    my ($volume, $dir) = File::Spec->splitpath($path);
    my $folder = File::Spec->catpath($volume, $dir, '');
    make_path($folder) unless -d $folder;
    my ($fh, $tmp) = tempfile('.config-XXXXXX', DIR => $folder, UNLINK => 1);
    binmode $fh;
    print {$fh} JSON::PP->new->utf8->pretty->canonical->encode($config);
    close $fh or die "$tmp: $!\n";
    rename $tmp, $path or die "$path: $!\n";
    print "Saved: $path\n";
} else { die "Unknown settings command: $action\n"; }
