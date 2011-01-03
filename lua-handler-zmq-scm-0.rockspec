#!/usr/bin/env lua

package	= 'lua-handler-zmq'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-handlers.git'
}
description	= {
	summary	= "ZeroMQ async. handler class.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'lua-ev',
	'lua-zmq',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.zmq']  = "handler/zmq.lua",
		}
	}
}
