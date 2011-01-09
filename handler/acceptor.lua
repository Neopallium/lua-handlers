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
local tostring = tostring
local print = print
local assert = assert

local socket = require"socket"
local ev = require"ev"
local connection = require"handler.connection"
local wrap_connected = connection.wrap_connected

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

local function acceptor_new_bind_listen(loop, handler, is_dgram, addr, port, backlog)
	local server

	-- setup server socket.
	if is_dgram then
		server = socket.udp()
	else
		server = socket.tcp()
	end
	assert(server:setoption('reuseaddr', true), 'server:setoption failed')
	-- bind server
	if is_dgram then
		assert(server:setsockname(addr, port))
	else
		assert(server:bind(addr, port))
		assert(server:listen(backlog or 256))
	end

	-- create acceptor
	local self = {
		loop = loop,
		handler = handler,
		server = server,
		addr = addr,
		port = port,
		-- max sockets to try to accept on one event
		accept_max = 100,
		backlog = backlog,
	}
	setmetatable(self, acceptor_mt)

	-- set socket to non-blocking mode.
	server:settimeout(0)

	-- create callback closure
	local accept_cb
	if is_dgram then
		local udp_clients = setmetatable({}, {__mode="v"})
		accept_cb = function()
			local max = self.accept_max
			local count = 0
			repeat
				local data, c_ip, c_port = server:receivefrom(8192)
				if data then
					local client
					local c_key = c_ip .. tostring(c_port)
					-- look for existing client socket.
					local sock = udp_clients[c_key]
					-- check if socket is still valid
					if sock and sock:is_closed() then
						sock = nil
					end
					-- if no cached socket, make a new one.
					if not sock then
						sock = socket.udp()
						assert(sock:setoption('reuseaddr', true), 'server:setoption failed')
						-- bind client socket to same addr:port as server socket.
						assert(sock:setsockname(addr, port))
						-- connect socket to client's ip:port
						assert(sock:setpeername(c_ip, c_port))
						-- wrap lua socket.
						sock = wrap_connected(loop, nil, sock)
						udp_clients[c_key] = sock
						-- pass client socket to new connection handler.
						if handler(sock) == nil then
							-- connect handler returned nil, maybe they are rejecting connections.
							break
						end
						-- get socket handler object from socket
						client = sock.handler
						-- call connected callback, socket is ready for sending data.
						client:handle_connected()
					else
						-- get socket handler object from socket
						client = sock.handler
					end
					-- handle datagram from udp client.
					client:handle_data(data)
				else
					local err = c_ip
					if err ~= 'timeout' then
						print('dgram_accept.error:', err)
					end
					break
				end
				count = count + 1
			until count >= max
		end
	else
		accept_cb = function()
			local max = self.accept_max
			local count = 0
			repeat
				local sock, err = server:accept()
				if sock then
					-- wrap lua socket
					sock = wrap_connected(loop, nil, sock)
					if handler(sock) == nil then
						-- connect handler returned nil, maybe they are rejecting connections.
						break
					end
					-- get socket handler object from socket
					local client = sock.handler
					-- call connected callback, socket is ready for sending data.
					client:handle_connected()
				else
					if err ~= 'timeout' then
						print('stream_accept.error:', err)
					end
					break
				end
				count = count + 1
			until count >= max
		end
	end
	-- create IO watcher.
	local fd = server:getfd()
	self.io = ev.IO.new(accept_cb, fd, ev.READ)

	self.io:start(loop)

	return self
end

module'handler.acceptor'

function tcp(loop, handler, addr, port, backlog)
	return acceptor_new_bind_listen(loop, handler, false, addr, port, backlog)
end

function udp(loop, handler, addr, port, backlog)
	return acceptor_new_bind_listen(loop, handler, true, addr, port, backlog)
end

