local setmetatable = setmetatable
local print = print
local assert = assert

local socket = require"socket"
local ev = require"ev"

local acceptor_mt = {
set_accept_max = function(this, max)
	this.accept_max = max
end,
close = function(this)
	this.io:stop(this.loop)
	this.server:close()
end,
}
acceptor_mt.__index = acceptor_mt

local function acceptor_wrap(loop, handler, server, backlog)
	-- create acceptor
	local this = {
		loop = loop,
		handler = handler,
		server = server,
		-- max sockets to try to accept on one event
		accept_max = 100,
		backlog = backlog,
	}
	setmetatable(this, acceptor_mt)

	server:settimeout(0)
	-- create callback closure
	local accept_cb = function()
		repeat
			local sck, err = server:accept()
			if sck then
				handler(sck)
			else
				if err ~= 'timeout' then
				end
				break
			end
		until not err
	end
	-- create IO watcher.
	local fd = server:getfd()
	this.io = ev.IO.new(accept_cb, fd, ev.READ)

	this.io:start(loop)

	return this
end

module(...)

function new(loop, handler, addr, port, backlog)
	-- setup server socket.
	local server = socket.tcp()
	server:settimeout(0)
	assert(server:setoption('reuseaddr', true), 'server:setoption failed')
	-- bind server
	assert(server:bind(addr, port))
	assert(server:listen(backlog or 256))

	-- wrap server socket
	this = acceptor_wrap(loop, handler, server)
	return this
end

function wrap(loop, handler, server)
	-- make server socket non-blocking.
	server:settimeout(0)
	-- wrap server socket
	this = acceptor_wrap(loop, handler, server)
	return this
end

