#!/usr/bin/env perl
# Device discovery and per-stream playback, shared by every agent adapter.
use strict;
use warnings;
use JSON::PP;
use File::Basename qw(dirname);
use File::Spec;
use File::Path qw(make_path);
use File::Temp qw(tempfile);
use Digest::SHA qw(sha256_hex);
my $core = dirname(File::Spec->rel2abs(__FILE__));
sub executable {
    my ($name) = @_;
    for my $dir (split /:/, $ENV{PATH} // '') { return "$dir/$name" if -f "$dir/$name" && -x "$dir/$name"; }
    return;
}
sub capture {
    my @command = @_;
    open my $fh, '-|', @command or die "$command[0]: $!\n";
    local $/; my $out = <$fh> // '';
    close $fh or die "$command[0] failed\n";
    return $out;
}
sub windows_command {
    my $ps = executable('powershell.exe') or die "Windows PowerShell interop is unavailable\n";
    my $wslpath = executable('wslpath') or die "Windows audio routing needs WSL interop\n";
    my $script = capture($wslpath, '-w', "$core/windows-audio.ps1"); chomp $script;
    return ($ps, '-NoProfile', '-NonInteractive', '-File', $script);
}
sub macos_helper {
    my $cc = executable('cc') or die "Device selection on macOS requires Xcode Command Line Tools (cc)\n";
    # Check before invoking Apple's cc shim, which may otherwise prompt to install.
    capture('xcode-select', '-p');
    open my $source, '<:raw', "$core/macos-audio.c" or die $!;
    local $/; my $hash = sha256_hex(<$source>);
    my $base = $ENV{XDG_CACHE_HOME} // "$ENV{HOME}/.cache";
    my $folder = "$base/robotspeak-agents";
    make_path($folder, {mode => 0700}) unless -d $folder;
    my $binary = "$folder/macos-audio-$hash";
    unless (-x $binary) {
        my ($fh, $tmp) = tempfile('macos-build-XXXXXX', DIR => $folder, UNLINK => 1); close $fh;
        system($cc, '-std=c11', '-Wall', '-Wextra', '-O2', "$core/macos-audio.c", '-framework', 'CoreAudio', '-framework', 'AudioToolbox', '-framework', 'CoreFoundation', '-o', $tmp) == 0 or die "macOS audio helper compilation failed\n";
        chmod 0700, $tmp;
        rename $tmp, $binary or die "$binary: $!\n";
    }
    return $binary;
}
my $action = shift(@ARGV) // 'list';
if ($action eq 'list') {
    my @devices;
    if ($^O eq 'darwin') {
        my $devices = decode_json(capture(macos_helper(), 'list'));
        push @devices, map { {id => "macos:$_->{id}", name => $_->{name}} } @$devices;
    } else {
        if (executable('wslpath') && executable('powershell.exe')) {
            my $devices = decode_json(capture(windows_command(), '-ListDevices'));
            push @devices, map { {id => "windows:$_->{id}", name => $_->{name}} } @$devices;
        }
        my @linux;
        if (executable('pactl')) {
            # PulseAudio's compatible interface also works with PipeWire and WSLg.
            my $sinks = eval { decode_json(capture('pactl', '-f', 'json', 'list', 'sinks')) };
            if ($sinks) {
                push @linux, map { {id => "pulse:$_->{name}", name => ($_->{description} // $_->{name})} } @$sinks;
            }
        }
        if (!@linux && executable('pw-dump')) {
            my $objects = decode_json(capture('pw-dump'));
            for my $object (@$objects) {
                my $props = $object->{info}{props} // {};
                next unless ($props->{'media.class'} // '') eq 'Audio/Sink';
                push @linux, { id => 'pipewire:' . $props->{'node.name'}, name => ($props->{'node.description'} // $props->{'node.name'}) };
            }
        }
        if (!@linux && executable('aplay')) {
            my $listing = capture('aplay', '-L');
            while ($listing =~ /^([^\s]+)\n(?:[ \t]+([^\n]+))?/mg) {
                push @linux, {id => "alsa:$1", name => ($2 // $1)};
            }
        }
        push @devices, @linux;
    }
    print JSON::PP->new->utf8->pretty->encode(\@devices);
} elsif ($action eq 'play') {
    die "Usage: play <backend:identifier> <WAV>\n" unless @ARGV == 2;
    my ($device, $file) = @ARGV;
    my ($backend, $id) = split /:/, $device, 2;
    die "Missing audio device identifier\n" unless $device eq 'default' || (defined $id && length $id);
    my @command;
    if ($device eq 'default') {
        if ($^O eq 'darwin') { @command = ('afplay', $file); }
        elsif (($ENV{ROBOTSPEAK_ENGINE} // '') ne 'perl' && executable('wslpath') && executable('powershell.exe')) {
            my $path = capture('wslpath', '-w', File::Spec->rel2abs($file)); chomp $path;
            @command = (windows_command(), '-Device', 'default', '-File', $path);
        } else {
            my ($player) = grep { executable($_) } qw(paplay pw-play aplay);
            die "No Linux audio player available\n" unless $player;
            @command = ($player, $file);
        }
    } elsif ($backend eq 'windows') {
        my $path = capture('wslpath', '-w', File::Spec->rel2abs($file)); chomp $path;
        @command = (windows_command(), '-Device', $id, '-File', $path);
    } elsif ($backend eq 'macos' && $^O eq 'darwin') {
        @command = (macos_helper(), 'play', $id, $file);
    } elsif ($backend eq 'pulse') {
        @command = ('paplay', '--device='.$id, $file);
    } elsif ($backend eq 'pipewire') {
        @command = ('pw-play', '--target='.$id, '--properties={"node.dont-fallback":true,"node.dont-reconnect":true,"node.dont-move":true}', $file);
    } elsif ($backend eq 'alsa') {
        @command = ('aplay', '-q', '-D', $id, $file);
    } else { die "Unsupported audio backend on this platform: $backend\n"; }
    system(@command) == 0 or die "Playback failed on selected device: $device\n";
} else { die "Unknown audio command: $action\n"; }
