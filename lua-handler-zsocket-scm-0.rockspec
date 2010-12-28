#!/usr/bin/env lua

package	= 'lua-handler-zsocket'
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
	'lua-handler',
	'lua-zmq',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.zsocket']  = "handler/zsocket.lua",
		}
	}
}
