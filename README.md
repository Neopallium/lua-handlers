lua-handlers
==============

Provides a set of async. callback based handlers for working with raw TCP/UDP socket, ZeroMQ sockets, or HTTP requests.


Installing
----------

Install base package lua-handler:

curl -O "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"

luarocks install lua-ev-scm-1.rockspec

luarocks install luasocket

curl -O "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-scm-0.rockspec"

luarocks install lua-handler-scm-0.rockspec


Install optional sub-package lua-handler-http:

curl -O "https://github.com/Neopallium/lua-http-parser/raw/master/lua-http-parser-scm-0.rockspec"

luarocks install lua-http-parser-scm-0.rockspec

curl -O "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-http-scm-0.rockspec"

luarocks install lua-handler-http-scm-0.rockspec


Install optional sub-package lua-handler-zsocket:

curl -O "https://github.com/iamaleksey/lua-zmq/raw/master/rockspecs/lua-zmq-scm-0.rockspec"

luarocks install lua-zmq-scm-0.rockspec

curl -O "https://github.com/Neopallium/lua-handlers/raw/master/lua-handler-zsocket-scm-0.rockspec"

luarocks install lua-handler-zsocket-scm-0.rockspec


Dependencies
------------
Base lua-handler package required dependcies:

* [Lua](http://www.lua.org/)
* [Lua-ev](https://github.com/brimworks/lua-ev)
* [LuaSocket](http://w3.impa.br/~diego/software/luasocket/)

Dependencies for optional lua-handler-http package:

* [Lua-http-parser](https://github.com/Neopallium/lua-http-parser)

Dependencies for optional lua-handler-zsocket package:

* [ZeroMQ](http://www.zeromq.org/) requires at least 2.1.0
* [ZeroMQ-lua](http://github.com/Neopallium/lua-zmq)

