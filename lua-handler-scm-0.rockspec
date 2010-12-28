#!/usr/bin/env lua

package	= 'lua-handler'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-handlers.git'
}
description	= {
	summary	= "Socket handler class that wrap lua-ev/luasocket.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'lua >= 5.1',
	'luasocket',
	'lua-ev',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.acceptor'] = "handler/acceptor.lua",
			['handler.tcp']  = "handler/tcp.lua",
			['handler.udp']  = "handler/udp.lua",
		}
	}
}
