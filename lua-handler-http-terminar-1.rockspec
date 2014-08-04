#!/usr/bin/env lua

package	= 'lua-handler-http'
version	= 'terminar-1'
source	= {
	url	= 'git://github.com/terminar/lua-handlers.git'
}
description	= {
	summary	= "HTTP client handler class.",
	detailed	= '',
	homepage	= 'https://github.com/terminar/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'lua-handler',
	'lua-http-parser',
	'luasocket',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.http.client']  = "handler/http/client.lua",
			['handler.http.client.connection']  = "handler/http/client/connection.lua",
			['handler.http.client.hosts']  = "handler/http/client/hosts.lua",
			['handler.http.client.request']  = "handler/http/client/request.lua",
			['handler.http.client.response']  = "handler/http/client/response.lua",
			['handler.http.chunked']  = "handler/http/chunked.lua",
			['handler.http.server']  = "handler/http/server.lua",
			['handler.http.server.hconnection']  = "handler/http/server/hconnection.lua",
			['handler.http.server.error_handler']  = "handler/http/server/error_handler.lua",
			['handler.http.server.request']  = "handler/http/server/request.lua",
			['handler.http.server.response']  = "handler/http/server/response.lua",
			['handler.http.headers']  = "handler/http/headers.lua",
			['handler.http.file']  = "handler/http/file.lua",
			['handler.http.form']  = "handler/http/form.lua",
		}
	}
}
