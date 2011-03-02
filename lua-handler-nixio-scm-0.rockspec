#!/usr/bin/env lua

package	= 'lua-handler-nixio'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-handlers.git'
}
description	= {
	summary	= "Depercated module.  Nixio is now the main socket backend.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-handlers',
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
			['handler.nixio.acceptor']  = "handler/nixio/acceptor.lua",
			['handler.nixio.connection']  = "handler/nixio/connection.lua",
			['handler.nixio.datagram']  = "handler/nixio/datagram.lua",
		}
	}
}
