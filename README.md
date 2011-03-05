lua-handlers
==============

Provides a set of async. callback based handlers for working with raw TCP/UDP socket, ZeroMQ sockets, or HTTP client/server.


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

### Dependencies for optional lua-handler-zmq package:

* [Lua-ev](https://github.com/brimworks/lua-ev)
* [ZeroMQ](http://www.zeromq.org/) requires at least 2.1.0
* [ZeroMQ-lua](http://github.com/Neopallium/lua-zmq)

