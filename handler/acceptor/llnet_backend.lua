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
local error = error
local assert = assert
local tostring = tostring
local tonumber = tonumber

local handler = require"handler"
local poll = handler.get_poller()

local llnet = require"llnet"
local get_opt = llnet.GetSocketOption
local set_opt = llnet.SetSocketOption
local new_socket = llnet.LSocket
local AF_UNIX = llnet.AF_UNIX
local AF_INET = llnet.AF_INET
local AF_INET6 = llnet.AF_INET6
local SOCK_STREAM = llnet.SOCK_STREAM
local SOCK_DGRAM = llnet.SOCK_DGRAM

-- for nixio.fs
local nixio = require"nixio"

local connection = require"handler.connection"
local wrap_connected = connection.wrap_connected
local tls_connection = require"handler.connection.tls_backend"
local tls_wrap_connected = connection.tls_wrap_connected

local uri_mod = require"handler.uri"
local uri_parse = uri_mod.parse
local query_parse = uri_mod.parse_query

local function make_addr(addr, host, port)
	addr = addr or llnet.LSockAddr()
	if host == '*' or host == nil then host = '0.0.0.0' end
	addr:set_ip_port(host, tonumber(port))
	return addr
end

local function new_addr(host, port)
	return make_addr(nil, host, port)
end

local tmp_addr = llnet.LSockAddr()
local function make_tmp_addr(host, port)
	return make_addr(tmp_addr, host, port)
end

local acceptor_mt = {
set_accept_max = function(self, max)
	self.accept_max = max
end,
close = function(self)
	poll:file_del(self)
	self.server:close()
end,
fileno = function(self)
	return self.server:fileno()
end,
}
acceptor_mt.__index = acceptor_mt

local function sock_new_bind_listen(handler, domain, stype, host, port, tls, backlog)
	local is_dgram = (stype == SOCK_DGRAM)
	-- 'backlog' is optional, it defaults to 256
	backlog = backlog or 256
	-- create socket
	local server = new_socket(domain, stype, 0, 0)

	-- create acceptor
	local self = {
		handler = handler,
		server = server,
		host = host,
		port = port,
		tls = tls,
		-- max sockets to try to accept on one event
		accept_max = 1000,
		backlog = backlog,
	}
	setmetatable(self, acceptor_mt)

	-- make socket non-blocking
	server:set_nonblock(true)
	-- create callback closure
	local accept_cb
	if is_dgram then
		local udp_clients = setmetatable({},{__mode="v"})
		local tmp_addr = llnet.LSockAddr()
		local bind_addr = new_addr(host, port)
		accept_cb = function()
			local max = self.accept_max
			local count = 0
			repeat
				local data, err = server:recvfrom(8192, 0, tmp_addr)
				if not data then
					if err ~= 'EAGAIN' then
						print('dgram_accept.error:', err)
					end
					break
				else
					local client
					local c_key = tmp_addr:todata()
					-- look for existing client socket.
					local sock = udp_clients[c_key]
					-- check if socket is still valid.
					if sock and sock:is_closed() then
						sock = nil
					end
					-- if no cached socket, make a new one.
					if not sock then
						-- make a duplicate server socket
						sock = new_socket(domain, stype)
						assert(set_opt.SO_REUSEADDR(sock, 1))
						assert(sock:bind(bind_addr))
						-- connect dupped socket to client's ip:port
						assert(sock:connect(tmp_addr))
						-- wrap socket
						sock = wrap_connected(nil, sock)
						udp_clients[c_key] = sock
						-- pass client socket to new connection handler.
						if handler(sock) == nil then
							-- connect handler returned nil, maybe they are rejecting connections.
							count = max -- early end of accept loop
						end
					end
					-- get socket handler object from socket
					client = sock.handler
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
				local sock, err = server:accept()
				if not sock then
					if err ~= 'EAGAIN' then
						print('stream_accept.error:', err)
					end
					break
				else
					-- wrap socket
					if tls then
						sock = tls_wrap_connected(nil, sock, tls)
					else
						sock = wrap_connected(nil, sock)
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
	-- enable read events.
	self.on_io_read = accept_cb
	poll:file_read(self, true)

	-- allow the address to be re-used.
	set_opt.SO_REUSEADDR(server, 1)
	-- defer accept until data or timeout.
	-- TODO: look into why this causes problems with accepting large number of sockets 50K
	--set_opt.TCP_DEFER_ACCEPT(server, 60)
	-- bind socket to local host:port
	assert(server:bind(make_tmp_addr(host, port)))
	if not is_dgram then
		-- set the socket to listening mode
		assert(server:listen(backlog))
	end

	return self
end

module(...)

function tcp6(handler, host, port, backlog)
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(handler, AF_INET6, SOCK_STREAM, host, port, nil, backlog)
end

function tcp(handler, host, port, backlog)
	if host:sub(1,1) == '[' then
		return tcp6(handler, host, port, backlog)
	else
		return sock_new_bind_listen(handler, AF_INET, SOCK_STREAM, host, port, nil, backlog)
	end
end

function tls_tcp6(handler, host, port, tls, backlog)
	error("Not implemented!")
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(handler, AF_INET6, SOCK_STREAM, host, port, tls, backlog)
end

function tls_tcp(handler, host, port, tls, backlog)
	error("Not implemented!")
	if host:sub(1,1) == '[' then
		return tls_tcp6(handler, host, port, tls, backlog)
	else
		return sock_new_bind_listen(handler, AF_INET, SOCK_STREAM, host, port, tls, backlog)
	end
end

function udp6(handler, host, port, backlog)
	-- remove '[]' from IPv6 addresses
	if host:sub(1,1) == '[' then
		host = host:sub(2,-2)
	end
	return sock_new_bind_listen(handler, AF_INET6, SOCK_DGRAM, host, port, nil, backlog)
end

function udp(handler, host, port, backlog)
	if host:sub(1,1) == '[' then
		return udp6(handler, host, port, backlog)
	else
		return sock_new_bind_listen(handler, AF_INET, SOCK_DGRAM, host, port, nil, backlog)
	end
end

function unix(handler, path, backlog)
	-- check if socket already exists.
	local stat, errno, err = nixio.fs.lstat(path)
	if stat then
		-- socket already exists, try to delete it.
		local stat, errno, err = nixio.fs.unlink(path)
		if not stat then
			print('Warning failed to delete old Unix domain socket: ', err)
		end
	end
	return sock_new_bind_listen(handler, AF_UNIX, SOCK_STREAM, path, nil, nil, backlog)
end

function uri(handler, uri, backlog, default_port)
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
		return unix(handler, uri.path, backlog)
	else
		local host, port = uri.host, uri.port or default_port
		if scheme == 'tcp' then
			return tcp(handler, host, port, backlog)
		elseif scheme == 'tcp6' then
			return tcp6(handler, host, port, backlog)
		elseif scheme == 'udp' then
			return udp(handler, host, port, backlog)
		elseif scheme == 'udp6' then
			return udp6(handler, host, port, backlog)
		else
			-- create TLS context
			error("Not implemented!")
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
				return tls_tcp(handler, host, port, tls, backlog)
			elseif scheme == 'tls6' then
				return tls_tcp6(handler, host, port, tls, backlog)
			end
		end
	end
	error("Unknown listen URI scheme: " .. scheme)
end

