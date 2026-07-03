#!/usr/bin/env perl
# Regression test: run zzclone against the canned fake-zfs world in
# t/shims across all option combinations and compare the generated
# commands (stdout, stderr and exit code) with the files in t/expected.
# The fake dataset tree covers the incremental, full-send, up-to-date,
# no-snapshot, resume-token and guid-mismatch code paths, in local,
# remote-source and remote-destination flavours.
#
# Run with:  prove t/
# After an intentional output change, regenerate the expected files with:
#   UPDATE_EXPECTED=1 prove t/
use strict;
use warnings;
use FindBin;

my $script = "$FindBin::Bin/../zzclone";
my $shims  = "$FindBin::Bin/shims";
my $expdir = "$FindBin::Bin/expected";
my $tmpdir = ($ENV{TMPDIR} // '/tmp') . "/zzclone-test-$$";
mkdir $tmpdir or die "cannot create $tmpdir: $!\n";
END { unlink glob "$tmpdir/*"; rmdir $tmpdir if $tmpdir; }

$ENV{PATH} = "$shims:$ENV{PATH}";

my @cases = (
    [ 'help',        '--help' ],
    [ 'noargs' ],
    [ 'plain',       qw(tank/data back/data) ],
    [ 'lastonly',    qw(-l tank/data back/data) ],
    [ 'sync',        qw(-s tank/data back/data) ],
    [ 'syncroll',    qw(-s -R tank/data back/data) ],
    [ 'resume',      qw(-r tank/data back/data) ],
    [ 'resumechain', qw(-r -c tank/data back/data) ],
    [ 'syncchain',   qw(-s -c tank/data back/data) ],
    [ 'all-options', qw(-s -R -c -v -r tank/data back/data) ],
    [ 'remote-src',  qw(-s -R -c -r --sudo fake:tank/data back/data) ],
    [ 'remote-dst',  qw(-s -R -c -r --remote-sudo tank/data fake:back/data) ],
    [ 'local-sudo',  qw(-s --local-sudo tank/data back/data) ],
    [ 'both-remote', qw(fake:tank/data fake:back/data) ],
    [ 'watchdog',    qw(-r -W 300 tank/data back/data) ],
    [ 'rollback-F',  qw(-R tank/data back/data) ],
    [ 'overwrite',   qw(-R -F tank/data back/data) ],
);

sub slurp {
    my $file = shift;
    open my $fh, '<', $file or return undef;
    local $/;
    my $data = <$fh>;
    return $data // '';
}

sub spew {
    my ($file, $content) = @_;
    open my $fh, '>', $file or die "cannot write $file: $!\n";
    print $fh $content;
}

# Run one case, returning normalized stdout (with the exit code appended,
# so it is part of the comparison) and stderr. The script's own path
# appears in the usage text via $0; normalize it so the expected files do
# not depend on where the checkout lives.
sub run_case {
    my @args = @_;
    my $rc = system("perl \Q$script\E @args >\Q$tmpdir\E/out 2>\Q$tmpdir\E/err");
    my %stream = (
        out => slurp("$tmpdir/out") . "exit=" . ($rc >> 8) . "\n",
        err => slurp("$tmpdir/err"),
    );
    s/\Q$script\E/ZZCLONE/g for values %stream;
    return %stream;
}

my $update = $ENV{UPDATE_EXPECTED};
printf "1..%d\n", 2 * @cases;
my $n = 0;
my $failed = 0;

for my $case (@cases) {
    my ($name, @args) = @$case;
    my %got = run_case(@args);
    for my $stream (qw(out err)) {
        $n++;
        my $file = "$expdir/$name.$stream";
        if ($update) {
            spew($file, $got{$stream});
            print "ok $n - $name ($stream) [updated]\n";
            next;
        }
        my $expected = slurp($file);
        if (defined $expected && $got{$stream} eq $expected) {
            print "ok $n - $name ($stream)\n";
        } else {
            $failed++;
            print "not ok $n - $name ($stream)\n";
            spew("$tmpdir/expected", $expected // "<missing $file>\n");
            spew("$tmpdir/got", $got{$stream});
            print STDERR "# $name ($stream) differs from $file:\n";
            print STDERR "# $_\n" for split /\n/, `diff \Q$tmpdir\E/expected \Q$tmpdir\E/got`;
        }
    }
}

exit($failed ? 1 : 0);
