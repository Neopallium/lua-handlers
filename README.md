lua-handlers
==============

Socket & ZeroMQ handler classes that wrap lua-ev/lua-zmq/luasocket.


Installing
----------

curl -O "https://github.com/brimworks/lua-ev/raw/master/rockspec/lua-ev-scm-1.rockspec"
luarocks install lua-ev-scm-1.rockspec
curl -O "https://github.com/iamaleksey/lua-zmq/raw/master/rockspecs/lua-zmq-scm-0.rockspec"
luarocks install lua-zmq-scm-0.rockspec
curl -O "https://github.com/Neopallium/lua-handlers/raw/master/lua-handlers-scm-0.rockspec"
luarocks install lua-handlers-scm-0.rockspec


Dependencies
------------
* [Lua](http://www.lua.org/)
* [Lua-ev](https://github.com/brimworks/lua-ev)
* [ZeroMQ](http://www.zeromq.org/) requires at least 2.1.0
* [ZeroMQ-lua](http://github.com/Neopallium/lua-zmq)

