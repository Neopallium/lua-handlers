#!/usr/bin/env lua

package	= 'lua-handler'
version	= 'terminar-0'
source	= {
	url	= 'git://github.com/terminar/lua-handlers.git'
}
description	= {
	summary	= "Socket handler class that wrap lua-ev/nixio.",
	detailed	= '',
	homepage	= 'https://github.com/terminar/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'nixio',
	'lua-ev',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.acceptor'] = "handler/acceptor.lua",
			['handler.connection']  = "handler/connection.lua",
			['handler.connection.tls_backend']  = "handler/connection/tls_backend.lua",
			['handler.datagram']  = "handler/datagram.lua",
			['handler.uri']  = "handler/uri.lua",
		}
	}
}
