#!/usr/bin/env lua

package	= 'lua-handler-nixio'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-handlers.git'
}
description	= {
	summary	= "nixio socket handler class.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'lua-handler',
	'nixio',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.nixio.socket']  = "handler/nixio/socket.lua",
		}
	}
}
