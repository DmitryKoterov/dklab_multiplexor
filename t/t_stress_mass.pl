#!/usr/bin/perl -w

use IO::Socket;
use Time::HiRes qw(time usleep);

$| = 1;
print "Press Enter to create connections...\n"; scalar <STDIN>;

my @sock = ();
for (my $i = 0; $i < 100; $i++) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => '8088'
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

print "Press Enter to exit...\n"; scalar <STDIN>;

