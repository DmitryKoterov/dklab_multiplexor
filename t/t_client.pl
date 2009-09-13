#!/usr/bin/perl -w
use IO::Socket;
use threads;

# Re-run self with high ulimit.
if (($ARGV[0]||'') ne "-") {
	my $cmd = "/bin/sh -c 'ulimit -n 1048576; $^X \"$0\" - " . join(" ", map { '"' . $_ . '"' } @ARGV) . "'";
	exec($cmd) or die "Cannot exec $cmd: $!\n";
} else {
	shift @ARGV;
}


$| = 1;
print "Press Enter to create connections..."; scalar <STDIN>;

my @sock = ();
for (my $i = 0; $i < 10000; $i++) {
	my $sock = IO::Socket::INET->new(
		PeerAddr => '127.0.0.1',
		PeerPort => '8088'
	);
	if (!$sock) {
		print "$i: $@\n\n";
		exit;
	}
	push @sock, $sock;
	print $sock "test $i\n";
	print $sock "identifier=$i\n";
	print STDERR ".";
}
print "\nWaiting for responses...\n";

for (my $i = 0; $i < @sock; $i++) {
	my $sock = $sock[$i];
	while (<$sock>) {
		chomp;
		print "[$i]: $_\n";
	}
}
