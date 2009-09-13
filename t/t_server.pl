#!/usr/bin/perl -w

use IO::Socket;
use Time::HiRes qw(time usleep);

# Re-run self with high ulimit.
if (($ARGV[0]||'') ne "-") {
	my $cmd = "/bin/sh -c 'ulimit -n 1048576; $^X \"$0\" - " . join(" ", map { '"' . $_ . '"' } @ARGV) . "'";
	exec($cmd) or die "Cannot exec $cmd: $!\n";
} else {
	shift @ARGV;
}

$| = 1;
print "Press Enter to start sending...\n"; scalar <STDIN>;

my @sock = ();
for (my $i = 0; $i < 10000; $i++) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => '10010'
	);
	if (!$sock) {
		print "$i: $@\n\n";
		last;
	}
	push @sock, $sock;
	print $sock "test $i\n";
	print $sock "identifier=$i\n";
	print ".";
#	usleep(1000);
}

print "Press Enter to disconnect and apply commands...\n"; scalar <STDIN>;

