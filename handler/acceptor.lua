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
local tostring = tostring

local ev = require"ev"
local nixio = require"nixio"
local new_socket = nixio.socket
local connection = require"handler.nixio.connection"
local wrap_connected = connection.wrap_connected

local function n_assert(test, errno, msg)
	return assert(test, msg)
end

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

local function sock_new_bind_listen(loop, handler, domain, _type, host, port, backlog)
	local is_dgram = (_type == 'dgram')
	-- nixio uses nil to mean any local address.
	if host == '*' then host = nil end
	-- create nixio socket
	local server = new_socket(domain, _type)

	-- create acceptor
	local self = {
		loop = loop,
		handler = handler,
		server = server,
		host = host,
		port = port,
		-- max sockets to try to accept on one event
		accept_max = 100,
		backlog = backlog,
	}
	setmetatable(self, acceptor_mt)

	-- make nixio socket non-blocking
	server:setblocking(false)
	-- create callback closure
	local accept_cb
	if is_dgram then
		local udp_clients = setmetatable({},{__mode="v"})
		accept_cb = function()
			local max = self.accept_max
			local count = 0
			repeat
				local data, c_ip, c_port = server:recvfrom(8192)
				if not data then
					if data ~= false then
						print('dgram_accept.error:', c_ip, c_port)
					end
					break
				else
					local client
					local c_key = c_ip .. tostring(c_port)
					-- look for existing client socket.
					local sock = udp_clients[c_key]
					-- check if socket is still valid.
					if sock and sock:is_closed() then
						sock = nil
					end
					-- if no cached socket, make a new one.
					if not sock then
						-- make a duplicate server socket
						sock = new_socket(domain, _type)
						n_assert(sock:setsockopt('socket', 'reuseaddr', 1))
						n_assert(sock:bind(host, port))
						-- connect dupped socket to client's ip:port
						n_assert(sock:connect(c_ip, c_port))
						-- wrap nixio socket
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
					-- handle first data block from udp client
					client:handle_data(data)
				end
				count = count + 1
			until count >= max
		end
	else
		accept_cb = function()
			local max = self.accept_max
			local count = 0
			repeat
				local sock, errno, err = server:accept()
				if not sock then
					if sock ~= false then
						print('stream_accept.error:', errno, err)
					end
					break
				else
					-- wrap nixio socket
					sock = wrap_connected(loop, nil, sock)
					if handler(sock) == nil then
						-- connect handler returned nil, maybe they are rejecting connections.
						break
					end
					-- get socket handler object from socket
					local client = sock.handler
					-- call connected callback, socket is ready for sending data.
					client:handle_connected()
				end
				count = count + 1
			until count >= max
		end
	end
	-- create IO watcher.
	local fd = server:fileno()
	self.io = ev.IO.new(accept_cb, fd, ev.READ)

	self.io:start(loop)

	-- allow the address to be re-used.
	n_assert(server:setsockopt('socket', 'reuseaddr', 1))
	-- bind socket to local host:port
	n_assert(server:bind(host, port))
	if not is_dgram then
		-- set the socket to listening mode
		n_assert(server:listen(backlog or 256))
	end

	return self
end

module(...)

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

