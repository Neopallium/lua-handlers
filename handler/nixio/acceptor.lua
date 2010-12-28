-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local setmetatable = setmetatable
local print = print
local assert = assert

local ev = require"ev"
local nixio = require"nixio"
local new_socket = nixio.socket

local acceptor_mt = {
set_accept_max = function(self, max)
	self.accept_max = max
end,
close = function(self)
	self.io:stop(self.loop)
	self.server:close()
end,
}
acceptor_mt.__index = acceptor_mt

local function acceptor_wrap(loop, handler, server, is_udp, backlog)
	-- create acceptor
	local self = {
		loop = loop,
		handler = handler,
		server = server,
		-- max sockets to try to accept on one event
		accept_max = 100,
		backlog = backlog,
	}
	setmetatable(self, acceptor_mt)

	-- TODO: fix accepting of UDP sockets.

	-- make nixio socket non-blocking
	server:setblocking(false)
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
	local fd = server:fileno()
	self.io = ev.IO.new(accept_cb, fd, ev.READ)

	self.io:start(loop)

	return self
end

local function n_assert(test, errno, msg)
	return assert(test, msg)
end

local function sock_new_bind_listen(loop, handler, domain, _type, host, port, backlog)
	-- nixio uses nil to mean any local address.
	if host == '*' then host = nil end
	-- create nixio socket
	local sock = new_socket(domain, _type)
	-- wrap server socket
	local self = acceptor_wrap(loop, handler, (_type == 'dgram'), sock)
	-- allow the address to be re-used.
	n_assert(sock:setsockopt('socket', 'reuseaddr', 1), 'Failed to set reuseaddr option.')
	-- bind socket to local host:port
	n_assert(sock:bind(host, port))
	if _type == 'stream' then
		-- set the socket to listening mode
		n_assert(sock:listen(backlog or 256))
	end

	return self
end

module'handler.nixio.acceptor'

function tcp(loop, handler, host, port, backlog)
	return sock_new_bind_listen(loop, handler, 'inet', 'stream', host, port, backlog)
end

function tcp6(loop, handler, host, port, backlog)
	return sock_new_bind_listen(loop, handler, 'inet6', 'stream', host, port, backlog)
end

function udp(loop, handler, host, port, backlog)
	return sock_new_bind_listen(loop, handler, 'inet', 'dgram', host, port, backlog)
end

function udp6(loop, handler, host, port, backlog)
	return sock_new_bind_listen(loop, handler, 'inet6', 'dgram', host, port, backlog)
end

function unix(loop, handler, path, backlog)
	return sock_new_bind_listen(loop, handler, 'unix', 'stream', path, nil, backlog)
end

function wrap(loop, handler, server)
	return acceptor_wrap(loop, handler, sock)
end

