#!/usr/bin/env lua

package	= 'lua-handlers'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-ev-workers.git'
}
description	= {
	summary	= "Socket & ZeroMQ handler classes that wrap lua-ev/lua-zmq/luasocket.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-ev-workers',
	license	= 'MIT',
}
dependencies = {
	'lua >= 5.1',
	'lua-zmq',
	'lua-ev',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.acceptor'] = "handler/acceptor.lua",
			['handler.nsocket']  = "handler/nsocket.lua",
			['handler.zsocket']  = "handler/zsocket.lua",
		}
	}
}
