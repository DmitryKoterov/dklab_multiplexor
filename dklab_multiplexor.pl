#!/usr/bin/perl -w

##
## dklab_multiplexor: simple and lightweight HTTP persistent
## connection emulation for JavaScript. Tool to handle 1000000+ 
## parallel browser connections.
##
## version 1.42
## (C) dkLab, http://dklab.ru/lib/dklab_multiplexor/
## Changelog: http://github.com/DmitryKoterov/dklab_multiplexor/commits/master/
##

use strict;
BEGIN {
	if (!eval('use Event::Lib; 1')) { 
		print STDERR "Error: Event::Lib library is not found in your system.\n";
		print STDERR "You must install libevent and Event::Lib, e.g.:\n";
		print STDERR "# yum install libevent-devel\n"; 
		print STDERR "# perl -MCPAN -e \"install Event::Lib\"\n";
		print STDERR "(see http://monkey.org/~provos/libevent/ for details)\n";
		exit;
	}
}

# Commands to be sent (key is ID, value is commands list).
my %commands = ();
# Connected clients (key is ID, value is clients list).
my %clients = ();
# Online timeouts (key is ID, value is Event).
my %online = ();



##
## WAIT connection.
##
{{{
	package ClientWait;
	our @ISA = 'Event::Lib::Client';
	use Event::Lib;

	# Called on a new connection.
	sub new {
		my ($class, @args) = @_;
		my $self = $class->SUPER::new(@args);
		$self->{id} = undef;
		$self->{data} = "";
		return $self;
	}

	# Called when a data is available to read.
	sub onread {
		my ($self, $data) = @_;
		$self->SUPER::onread($data);

		# Data must be ignored, identifier is already extracted.
		if (defined $self->{id}) {
			return;
		}
		
		# Append data.
		$self->{data} .= $data;

		# Try to extract ID from the new data chunk.
		my $id = main::extract_id($self->{data});
		if (defined $id) {
			# ID is extracted! Ignore all other data.
			$self->{data} = undef; # GC
			$self->{id} = $id;
			$self->debug("registered");
			push @{$clients{$id}}, $self->fh;
			# Try to send pendings.
			main::send_pendings($id);
			# Reset online timer.
			if ($online{$id}) {
				$online{$id}->remove();
				delete $online{$id};
			}
			# Create new online timer, but do not start it - it is 
			# started at LAST connection close, later.
			$online{$id} = timer_new(sub { 
				delete $commands{$id}; 
				delete $online{$id};
				main::logger("client [$id] is now offline");
				# TODO: send offline message to the Server.
			});
			return;
		}
	
		# Check for the data overflow.
		if (length($self->{data}) > $self->server->{maxlen}) {
			die "overflow (received " . length($data) . " bytes total)\n";
		}
	}

	# Called on timeout (send error message).
	sub ontimeout {
		my ($self) = @_;
		my $fh = $self->fh;
		if ($fh) {
			print $fh $self->server->{disconnect_response};
			shutdown($fh, 2);
		}
		$self->SUPER::ontimeout();
	}

	# Called on client disconnect.
	sub DESTROY {
		my ($self) = @_;
		my $id = $self->{id};
		if (defined $id) {
			# Remove the client from all lists.
			@{$clients{$id}} = grep { $_ != $self->fh } @{$clients{$id}};
			delete $clients{$id} if !@{$clients{$id}};
			# Turn on or restart online timer.
			if ($online{$id}) {
				$online{$id}->remove(); # needed to avoid multiple addition of the same timer
				$online{$id}->add($self->server->{offline_timeout});
			}
		}
		$self->SUPER::DESTROY();
	}
	
	# Connection name is its ID.
	sub name {
		my ($self) = @_;
		return $self->{id};
	}
}}}



##
## IN connection.
##
{{{
	package ClientIn;
	our @ISA = 'Event::Lib::Client';
	use Event::Lib;
	use POSIX '_exit';
	
	# Called on a new connection.
	sub new {
		my ($class, @args) = @_;
		my $self = $class->SUPER::new(@args);
		$self->{id} = undef;
		$self->{data} = "";
		return $self;
	}

	# Called when a data is available to read.
	sub onread {
		my ($self, $data) = @_;
		$self->SUPER::onread($data);

		# Append data.
		$self->{data} .= $data;

		# Try to extract ID from the new data chunk or process a command.
		if (!defined $self->{id}) {
			my $id = main::extract_id($self->{data});
			if (defined $id) {
				# ID is extracted, save it.
				$self->debug("parsed client ID(s): [$id]");
				$self->{id} = $id;
			} else {
				# Process aux commands.
				if ($self->{data} =~ /^(ONLINE)\s*$/si) {
					my $cmd = uc $1;
					$self->debug("received aux command: $cmd");
					shutdown($self->fh, 0);
					my $method = "cmd_" . lc($cmd);
					$self->$method();
					return;
				}
			}
		}
	
		# Check for the data overflow.
		if (length($self->{data}) > $self->server->{maxlen}) {
			die "overflow (received " . length($data) . " bytes total)\n";
		}
	}
	
	# Called on timeout.
	sub ontimeout {
		my ($self) = @_;
		$self->SUPER::ontimeout();
		$self->{id} = undef;
	}

	# Called on error.	
	sub onerror {
		my ($self, $msg) = @_;
		$self->SUPER::onerror();
		$self->{id} = undef;
	}	

	# Called on server disconnect.
	sub DESTROY {
		my ($self) = @_;
		my $id = $self->{id};
		if (defined $id) {
		    # Multiple IDs may be specified separated by ",".
			foreach my $id (split /,/, $id) {
				# If the client is offline, exit now, do not add a command.
				if (!$online{$id}) {
					$self->debug("dropping command, client [$id] is offline");
					next;
				}
				# Add command to queue and set lifetime.
				$self->debug("adding command for [$id]");
				push @{$commands{$id}}, $self->{data};
				# Send pending commands.
				main::send_pendings($id);
			}
		}
		$self->SUPER::DESTROY();
	}
	
	# Command: fetch all online IDs.
	sub cmd_online {
		my ($self) = @_;
		my $pid = fork();
		if (!defined $pid) {
			$self->debug("cannot fork: $!");
		} elsif ($pid > 0) {
			# Parent process detaches.
			# Do nothing here.
		} else {
			# Child process. Print all (many!) identifiers.
			$self->debug("sending " . scalar(keys %online) . " online identifiers");
			my $fh = $self->fh;
			print $fh join(",", keys %online);
			print $fh "\n.";
			close($fh);
			# We MUST use _exit(0 to avoid destructor calls.
			_exit(0);
		}
	}
}}}



##
## Client abstraction.
##
{{{
	package Event::Lib::Client;
	use strict;

	
	# Called on new connection.
	# DO NOT save $event object here to avoid cyclic references!
	sub new {
		my ($class, $fh, $server) = @_;
		my $self = bless {
			fh     => $fh,
			server => $server,
			# Save peer address now, because it may be inaccessible
			# in case of the manual socket shutdown.
			addr   => ($fh->peerhost||'?') . ":" . ($fh->peerport||'?'),
		}, $class;
		$self->debug("connection opened");
		return $self;
	}


	# Called on connection close.
	sub DESTROY {
		my ($self) = @_;
		$self->debug("connection closed");
	}


	# Called on timeout.
	sub ontimeout {
		my ($self) = @_;
		$self->debug("timeout");
	}


	# Called on event exception.
	sub onerror {
		my ($self, $msg) = @_;
		$self->debug("error: $msg");
	}


	# Called on data read.
	sub onread {
		my ($self, $data) = @_;
		$self->debug("read " . length($data) . " bytes");
	}


	# Returns the socket.
	sub fh {
		my ($self) = @_;
		return $self->{fh};
	}


	# Returns the server.
	sub server {
		my ($self) = @_;
		return $self->{server};
	}

	# Returns this connection name.
	sub name {
		return undef;
	}

	# Prints a debug message.
	sub debug {
		my ($self, $msg) = @_;
		my $name = $self->name;
		$self->{server}->debug($self->{addr}, ($name? "[$name] " : "") . $msg);
	}
}}}



##
## Server abstraction,
##
{{{
	package Event::Lib::Server;

	use strict;
	use IO::Socket::INET;
	use Event::Lib;
	use Carp;


	# Static function.
	# Runs the event mainloop.
	sub mainloop {
		event_mainloop();
	}


	# Creates a new server pool.
	sub new {
		my ($class, %params) = @_;
		my $self = bless {
			%params,
			name    => ($params{name} or croak "Argument 'name' required"),
			listen  => ($params{listen} or croak "Argument 'listen' required"),
			timeout => ($params{timeout} or croak "Argument 'timeout' required"),
			clientclass => ($params{clientclass} or croak "Argument 'clientclass' required"),
		}, $class;
		my @events = ();
		eval {
			foreach my $addr (@{$self->{listen}}) {
				push @events, $self->add_listen($addr);
			}
		};
		if ($@) {
			$_->remove() foreach @events;
			croak $@;
		}
		return $self;
	}


	# Adds a new listen address to the pool.
	# Croaks in case of error.
	sub add_listen {
		my ($self, $addr) = @_;
		my $server = IO::Socket::INET->new(
			LocalAddr   => $addr,
			Proto       => 'tcp',
			ReuseAddr   => SO_REUSEADDR,
			Listen      => 50000,
			Blocking    => 0,
		) or croak $@;
		my $event  = event_new(
			$server, EV_READ|EV_PERSIST, 
			\&handle_connect,
			$self
		);
		$event->add();
		$self->message(undef, "listening $addr");
		return $event;
	}


	sub handle_connect {
		my ($e, $type, $self) = @_;
		eval {
			my $t0 = time();
			my $socket = $e->fh->accept() or die "accept failed: $@";
			$socket->blocking(0);
			my $t1 = time();
	#		print sprintf("--> %.2f ms\n", ($t1 - $t0) * 1000);
			
			# Try to add an event.
			my $event = event_new($socket, EV_READ|EV_PERSIST, \&handle_read);
			$event->add($self->{timeout});
			# If we are here, event is successfully added. Assign error handler.
			my $client = $self->{clientclass}->new($socket, $self);
			$event->args($self, $client);
			$event->except_handler(\&handle_except);
		};
		$self->error($e->fh, $@) if $@;
	}


	sub handle_read {
		my ($e, $type, $self, $client) = @_;
		eval {
			my $h = $e->fh;
		
			# Timeout?
			if ($type == EV_TIMEOUT) {
				$client->ontimeout();
				$e->remove();
				return;
			}
		
			# Read the next data chunk.
			local $/;
			my $data = <$h>;
		
			# End of the request reached.
			if (!defined $data) {
				$e->remove();
				return;
			}
		
			# Run data handler.
			$client->onread($data);
		};
		if ($@) {
			$self->error($e->fh, $@);
			$e->remove();
		}
	}


	sub handle_except {
		my ($e, $msg, $type, $self, $client) = @_;
		eval {
			$client->onerror($msg);
			$e->remove();
		};
		$self->error($e->fh, $@) if $@;
	}


	# Controls debug messages.
	sub debug {
		my ($self, $fh, $msg) = @_;
		$self->message($fh, "DEBUG: $msg");
	}


	# Controls error messages.
	sub error {
		my ($self, $fh, $msg) = @_;
		$self->message($fh, "ERROR: $msg");
	}


	# Controls info messages.
	sub message {
		my ($self, $addr, $msg) = @_;
		chomp($msg);
		if (ref $addr) {
			$addr = ($addr->peerhost||'?') . ":" . ($addr->peerport||'?');
		}
		$msg = $addr . ": " . $msg if $addr;
		$msg = $self->{name} . ": " . $msg;
		if (exists $self->{logger}) {
			$self->{logger}->($msg) if $self->{logger};
		} else {
			print "[" . localtime(time) . "] $msg\n";
		}
	}
}}}



##
## Main program code.
##
{{{
	package main;

	# Loaded configuration.
	our %CONFIG;
	
	# Extracts ID from the client data. 
	# Returns this ID or undef if no ID is found yet.
	sub extract_id {
		my $rdata = \$_[0];
		return $$rdata =~ /\b$CONFIG{IDENTIFIER}=([\w,]+)\W/s? $1 : undef;
	}

	# Send first pending command to clients with specified ID.
	# Removes sent command from the queue and closes connections to clients.
	sub send_pendings {
		my ($id) = @_;
		return if !$clients{$id} || !@{$clients{$id}};
		return if !$commands{$id} || !@{$commands{$id}};
		my $data = shift @{$commands{$id}};
		while (my $fh = shift @{$clients{$id}}) {
			my $r1 = print $fh $data;
			my $r2 = shutdown($fh, 2);
			logger("<- sending " . length($data) . " bytes to [$id] (print=$r1, shutdown=$r2)");
		}
		# Free the memory used by empty lists.
		delete $commands{$id} if !@{$commands{$id}};
		delete $clients{$id} if !@{$clients{$id}};
	}

	# Logger routine.
	sub logger {
		my ($msg, $nostat) = @_;
		$msg = $msg . "\n  " . sprintf("[cmd_que_sz=%d conn=%d online=%d] ", scalar(keys %commands), scalar(keys %clients), scalar(keys %online)) if !$nostat;
		print "[" . localtime(time) . "] $msg\n";
	}

	# Main processing loop.
	sub mainloop {
		# Greetings.
		my $ulimit = `/bin/sh -c "ulimit -n"`; chomp $ulimit;
		logger("Starting. Opened files limit (ulimit -n): $ulimit.");
		
		# Read default config.
		require "dklab_multiplexor.conf";
		
		# Read custom config.
		if (@ARGV) {
			my $f = $ARGV[0];
			if (-f $f) {
				logger("CONFIG: appending configuration from $f");
				require $f;
			} else {
				logger("CONFIG: file $f does not exist, skipping");
			}
		}
		
		my $wait = Event::Lib::Server->new(
			name => "WAIT",
			listen => $CONFIG{WAIT_ADDR},
			timeout => $CONFIG{WAIT_TIMEOUT},
			clientclass => "ClientWait",
			maxlen => $CONFIG{WAIT_MAXLEN},
			logger => \&logger,
			offline_timeout => $CONFIG{OFFLINE_TIMEOUT},
			disconnect_response => $CONFIG{DISCONNECT_RESPONSE}
		);
		
		my $in = Event::Lib::Server->new(
			name => "IN",
			listen => $CONFIG{IN_ADDR},
			timeout => $CONFIG{IN_TIMEOUT},
			clientclass => "ClientIn",
			maxlen => $CONFIG{IN_MAXLEN},
			logger => \&logger,
		);
		
		Event::Lib::Server::mainloop();
	}
	
	# Turn off buffering.
	$| = 1;
	
	# Re-run self with high ulimit.
	if (($ARGV[0]||'') ne "-") {
		my $cmd = "/bin/sh -c 'ulimit -n 1048576; $^X \"$0\" - " . join(" ", map { '"' . $_ . '"' } @ARGV) . "'";
		exec($cmd) or die "Cannot exec $cmd: $!\n";
	} else {
		shift @ARGV;
	}

	# Turn on zombie auto-reaper.
	$SIG{CHLD} = 'IGNORE';

	while (1) {
		my $pid = fork();
		
		if (!$pid) {
			# Child process.
			mainloop();
			exit();
		}
		
		$SIG{HUP} = sub {
			# Kill the child, it will be restarted.
			logger("SIGHUP received, restarting the child");
			kill 9, $pid;
			return;
		};
		
		while (wait() != -1) {}
		sleep(1);
	}
}}}
