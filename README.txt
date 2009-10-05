dklab_multiplexor: tool to handle 1000000+ parallel browser connections.
(C) dkLab, http://dklab.ru/lib/dklab_multiplexor/
Changelog: http://github.com/DmitryKoterov/dklab_multiplexor/commits/master/



Usage samples
-------------

Be sure to install all needed libraries:

# yum install libevent-devel
# perl -MCPAN -e "install Event::Lib"

Run multiplexor daemon:

# cd /path/to/dklab_multiplexor
# perl dklab_multiplexor.pl >/var/log/multiplexor.log 2>&1 &

Now let's assume "we are the browser" - client with ID 1z2y3z
(in real case you would use JavaScript's XMLHttpRequest):

# wget -O- http://localhost:8088/?identifier=1z2y3z

A) Send data to an online client:
 
   $f = fsockopen("localhost", "10010");
   fwrite($f, 
     "HTTP/1.1 200 OK\n" .
     "X-Multiplexor: identifier=1z2y3z\n" .
     "\n" .
     "Hello!\n"
   );
   fclose($f);

B) Reveive the ","-separated list of all online IDs:

   $f = fsockopen("localhost", "10010");
   fwrite($f, "ONLINE\n");
   stream_socket_shutdown($f, STREAM_SHUT_WR);
   $ids = stream_get_contents($f);
   fclose($f);
   if (substr($ids, -1) == ".") {
     // Checked that ALL data is received ("." at the end).
     print_r(explode(",", trim(substr($ids, 0, -1))));
   }


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
