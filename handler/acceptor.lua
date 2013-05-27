-- Copyright (c) 2010-2011 by Robert G. Jakabosky <bobby@neoawareness.com>
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
local tonumber = tonumber
local error = error

local ev = require"ev"

local nixio = require"nixio"
local new_socket = nixio.socket

local connection = require"handler.connection"
local wrap_connected = connection.wrap_connected
local tls_connection = require"handler.connection.tls_backend"
local tls_wrap_connected = connection.tls_wrap_connected

local uri_mod = require"handler.uri"
local uri_parse = uri_mod.parse
local query_parse = uri_mod.parse_query

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

local function sock_new_bind_listen(loop, handler, domain, _type, host, port, tls, backlog)
	local is_dgram = (_type == 'dgram')
	-- nixio uses nil to mean any local address.
	if host == '*' then host = nil end
	-- 'backlog' is optional, it defaults to 256
	backlog = backlog or 256
	-- create nixio socket
	local server = new_socket(domain, _type)

	-- create acceptor
	local self = {
		loop = loop,
		handler = handler,
		server = server,
		host = host,
		port = port,
		tls = tls,
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
					if tls then
						sock = tls_wrap_connected(loop, nil, sock, tls)
					else
						sock = wrap_connected(loop, nil, sock)
					end
					if handler(sock) == nil then
						-- connect handler returned nil, maybe they are rejecting connections.
						break
					end
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
		n_assert(server:listen(backlog))
	end

	return self
end

module(...)

function tcp6(loop, handler, host, port, backlog)
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(loop, handler, 'inet6', 'stream', host, port, nil, backlog)
end

function tcp(loop, handler, host, port, backlog)
	if host:sub(1,1) == '[' then
		return tcp6(loop, handler, host, port, backlog)
	else
		return sock_new_bind_listen(loop, handler, 'inet', 'stream', host, port, nil, backlog)
	end
end

function tls_tcp6(loop, handler, host, port, tls, backlog)
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(loop, handler, 'inet6', 'stream', host, port, tls, backlog)
end

function tls_tcp(loop, handler, host, port, tls, backlog)
	if host:sub(1,1) == '[' then
		return tls_tcp6(loop, handler, host, port, tls, backlog)
	else
		return sock_new_bind_listen(loop, handler, 'inet', 'stream', host, port, tls, backlog)
	end
end

function udp6(loop, handler, host, port, backlog)
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(loop, handler, 'inet6', 'dgram', host, port, nil, backlog)
end

function udp(loop, handler, host, port, backlog)
	if host:sub(1,1) == '[' then
		return udp6(loop, handler, host, port, backlog)
	else
		return sock_new_bind_listen(loop, handler, 'inet', 'dgram', host, port, nil, backlog)
	end
end

function unix(loop, handler, path, backlog)
	-- check if socket already exists.
	local stat, errno, err = nixio.fs.lstat(path)
	if stat then
		-- socket already exists, try to delete it.
		local stat, errno, err = nixio.fs.unlink(path)
		if not stat then
			print('Warning failed to delete old Unix domain socket: ', err)
		end
	end
	return sock_new_bind_listen(loop, handler, 'unix', 'stream', path, nil, nil, backlog)
end

function uri(loop, handler, uri, backlog, default_port)
	local orig_uri = uri
	-- parse uri
	uri = uri_parse(uri)
	local scheme = uri.scheme
	assert(scheme, "Invalid listen URI: " .. orig_uri)
	local q = query_parse(uri.query)
	-- check if query has a 'backlog' parameter
	if q.backlog then
		backlog = tonumber(q.backlog)
	end
	-- use scheme to select socket type.
	if scheme == 'unix' then
		return unix(loop, handler, uri.path, backlog)
	else
		local host, port = uri.host, uri.port or default_port
		if scheme == 'tcp' then
			return tcp(loop, handler, host, port, backlog)
		elseif scheme == 'tcp6' then
			return tcp6(loop, handler, host, port, backlog)
		elseif scheme == 'udp' then
			return udp(loop, handler, host, port, backlog)
		elseif scheme == 'udp6' then
			return udp6(loop, handler, host, port, backlog)
		else
			-- create TLS context
			local tls = nixio.tls(q.mode or 'server') -- default to server-side
			-- set key
			if q.key then
				tls:set_key(q.key)
			end
			-- set certificate
			if q.cert then
				tls:set_cert(q.cert)
			end
			-- set ciphers
			if q.ciphers then
				tls:set_ciphers(q.ciphers)
			end
			if scheme == 'tls' then
				return tls_tcp(loop, handler, host, port, tls, backlog)
			elseif scheme == 'tls6' then
				return tls_tcp6(loop, handler, host, port, tls, backlog)
			end
		end
	end
	error("Unknown listen URI scheme: " .. scheme)
end

