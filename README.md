lua-handlers
==============

Provides a set of async. callback based handlers for working with raw TCP/UDP socket, ZeroMQ sockets, or HTTP client/server.


Socket connect/listen URI's
---------------------------

Different types of sockets can now be created from URI strings like `tcp://localhost:1234/` or `tls:/localhost:443/?key=examples/localhost.key&cert=examples/localhost.cert`.  URI's can be used for connecting sockets or listening sockets.

### TCP sockets

	tcp://<hostname or ip_address>:<optional port>/

### UDP sockets

	udp://<hostname or ip_address>:<optional port>/

### Unix domain sockets

	unix://<path to unix socket>

### SSL/TLS sockets over TCP

	tls://<hostname or ip_address>:<optional port>/?mode=<client/server>&key=<path to PEM private key>&cert=<path to PEM public certificate>

### To force IPv6 sockets

	tcp6://<hostname or ipv6_address>:<optional port>/
	udp6://<hostname or ipv6_address>:<optional port>/
	tls6://<hostname or ipv6_address>:<optional port>/?mode=<client/server>&key=<path to PEM private key>&cert=<path to PEM public certificate>


### Example server-side listen URIs:

	-- bind tcp socket to 127.0.0.1 on port 80 with an accept backlog of 1000
	tcp://localhost:80/?backlog=1000
	
	-- bind tcp socket to IPv6 address 2001:db8::1 on port 80 with an accept backlog of 1000
	tcp://[2001:db8::1]:80/?backlog=1000
	
	-- bind TLS wrapped tcp socket to 127.0.0.1 on port 443 with an accept backlog of 1000
	-- TLS defaults to mode=server when listening.
	tls://localhost:443/?backlog=1000&key=private_key.pem&cert=public_certificate.pem
	
	-- bind Unix domain socket to file /tmp/unix_server.sock
	unix:///tmp/unix_server.sock?backlog=100
	
	-- bind udp socket to 127.0.0.1 on port 53
	udp://localhost:53
	
	-- bind udp socket to IPv6 loop back address ::1 on port 53
	udp://[::1]:53
	or
	udp6://localhost:53

### Example client-side connect URIs:

	-- connect tcp socket to 127.0.0.1 on port 80
	tcp://localhost:80
	
	-- connect tcp socket to IPv6 address 2001:db8::1 on port 80
	tcp://[2001:db8::1]:80
	
	-- connect tcp socket to IPv6 address of hostname ipv6.google.com on port 80
	tcp6://ipv6.google.com:80
	
	-- connect TLS wrapped tcp socket to 127.0.0.1 on port 443
	-- TLS defaults to mode=client when connecting.
	tls://localhost:443
	
	-- connect Unix domain socket to file /tmp/unix_server.sock
	unix:///tmp/unix_server.sock
	
	-- connect udp socket to 127.0.0.1 on port 53
	udp://localhost:53
	
	-- connect udp socket to IPv6 loop back address ::1 on port 53
	udp://[::1]:53
	or
	udp6://localhost:53


Set local address & port when connecting
----------------------------------------

Sockets can be bound to a local address & port before connecting to the remote host:port.  For connecting URIs add parameters `laddr=<local address>&lport=<local port>`.

Examples:

	-- connect tcp socket to host www.google.com on port 80 and bind the socket to local address 192.168.0.1
	tcp://www.google.com/?laddr=192.168.0.1
	
	-- connect tcp socket to host www.google.com on port 80 and bind the socket to local address 192.168.0.1 and local port 16384
	tcp://www.google.com/?laddr=192.168.0.1&lport=16384
	
	-- connect udp socket to 10.0.0.10 on port 53 and bind to local address 10.100.100.1 and port 2053
	udp://10.0.0.10:53/?laddr=10.100.100.1&lport=2053


Example generic socket server & client
--------------------------------------

The generic server can listen on any number of sockets with different types.  The clients read stdin and send each line to the server which then re-sends the message to all connected clients.

Start generic socket server:
	lua examples/generic_chat_server.lua tcp://127.0.0.1:1080/ "tls://127.0.0.1:4433/?key=examples/localhost.key&cert=examples/localhost.cert" tcp://[::1]:1082/ unix:///tmp/test.sock?backlog=1234 udp6://localhost:2053

Start generic socket client:
	lua examples/generic_chat_client.lua tcp://localhost:1080
	-- or
	lua examples/generic_chat_client.lua udp6://localhost:2053
	-- or
	lua examples/generic_chat_client.lua tls://127.0.0.1:4433/
	-- or
	lua examples/generic_chat_client.lua tcp://[::1]:1082/
	-- or
	lua examples/generic_chat_client.lua unix:///tmp/test.sock

Installing
----------

### Install base package lua-handler:

	luarocks install "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"

	luarocks install "https://github.com/Neopallium/nixio/raw/master/nixio-scm-0.rockspec"

	luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"

### Install optional sub-package lua-handler-http:

	luarocks install "https://github.com/brimworks/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"

	luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"


### Install optional sub-package lua-handler-zmq:

	luarocks install "https://github.com/Neopallium/lua-zmq/raw/master/rockspecs/lua-zmq-scm-1.rockspec"

	luarocks install "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-zmq-scm-0.rockspec"


Dependencies
------------
### Base lua-handler package required dependcies:

* [Lua-ev](https://github.com/brimworks/lua-ev)
* [Nixio](https://github.com/Neopallium/nixio)

### Dependencies for optional lua-handler-http package:

* [Lua-ev](https://github.com/brimworks/lua-ev)
* [Lua-http-parser](https://github.com/brimworks/lua-http-parser)
* [LuaSocket](http://w3.impa.br/~diego/software/luasocket/), needed for the ltn12 sub-module.

### Dependencies for optional lua-handler-zmq package:

* [Lua-ev](https://github.com/brimworks/lua-ev)
* [ZeroMQ](http://www.zeromq.org/) requires at least 2.1.0
* [ZeroMQ-lua](http://github.com/Neopallium/lua-zmq)

