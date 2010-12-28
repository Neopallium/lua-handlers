#!/usr/bin/env lua

package	= 'lua-handler-http'
version	= 'scm-0'
source	= {
	url	= 'git://github.com/Neopallium/lua-handlers.git'
}
description	= {
	summary	= "HTTP client handler class.",
	detailed	= '',
	homepage	= 'https://github.com/Neopallium/lua-handlers',
	license	= 'MIT',
}
dependencies = {
	'lua-handler',
	'lua-http-parser',
}
build	= {
	type		= 'none',
	install = {
		lua = {
			['handler.http.client']  = "handler/http/client.lua",
			['handler.http.client.request']  = "handler/http/client/request.lua",
			['handler.http.client.hosts']  = "handler/http/client/hosts.lua",
			['handler.http.connection']  = "handler/http/connection.lua",
			['handler.http.headers']  = "handler/http/headers.lua",
			['handler.http.file']  = "handler/http/file.lua",
			['handler.http.form']  = "handler/http/form.lua",
		}
	}
}
