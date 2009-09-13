dklab_multiplexor: tool to handle 1000000+ parallel browser connections.
(C) dkLab, http://dklab.ru/lib/dklab_multiplexor/
Changelog: http://github.com/DmitryKoterov/dklab_multiplexor/commits/master/



Usage sample
------------

Be sure to install all needed libraries:

# yum install libevent-devel
# perl -MCPAN -e "install Event::Lib"

Run multiplexor daemon:

# cd /path/to/dklab_multiplexor
# perl dklab_multiplexor.pl >/var/log/multiplexor.log 2>&1 &

Now let's assume "we are the browser" - client with ID 1z2y3z
(in real case you would use JavaScript's XMLHttpRequest):

# wget -O- http://localhost:8088/?identifier=1z2y3z

In another console, now run something like this:

<?php
$f = fsockopen("localhost", "10010");
fwrite($f, 
  "HTTP/1.1 200 OK\n" .
  "X-Multiplexor: identifier=1z2y3z\n" .
  "\n" .
  "Hello!\n"
);
fclose($f);
?>



Log file mnemonics
------------------

cmd_que_sz
  Number of clients with non-empty command queue. This queue is used to 
  collect commands for clients which are disconnected no more than 
  OFFLINE_TIMEOUT seconds ago. Normally this number should be low.
  
conn
  Number of active TCP client connections. The same is the number of 
  waiting clients.
  
online
  The number of "online" clients. Client is treated as online if:
  - it has an active connection;
  - or it does not have a connection, but disconnected no more than
    OFFLINE_TIMEOUT seconds ago.
  So, this counter is not less than "conn" counter.
