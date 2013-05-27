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
local error = error

local ev = require"ev"
local nixio = require"nixio"
local new_socket = nixio.socket

local tls_backend = require"handler.connection.tls_backend"
local sock_tls_wrap = tls_backend.wrap

local uri_mod = require"handler.uri"
local uri_parse = uri_mod.parse
local query_parse = uri_mod.parse_query

local function n_assert(test, errno, msg)
	return assert(test, msg)
end

-- important errors
local EINPROGRESS = nixio.const.EINPROGRESS

local function sock_setsockopt(self, level, option, value)
	return self.sock:setsockopt(level, option, value)
end

local function sock_getsockopt(self, level, option)
	return self.sock:getsockopt(level, option)
end

local function sock_getpeername(self)
	return self.sock:getpeername()
end

local function sock_getsockname(self)
	return self.sock:getsockname()
end

local function sock_shutdown(self, read, write)
	local how = ''
	if read then
		how = 'rd'
		-- stop reading from socket, we don't want any more data.
		self.io_read:stop(self.loop)
	end
	if write then
		how = how .. 'wr'
	end
	return self.sock:shutdown(how)
end

local function sock_close(self)
	local sock = self.sock
	if not sock then return end
	self.is_closing = true
	self.read_blocked = true
	if not self.write_buf or self.has_error then
		local loop = self.loop
		if self.write_timer then
			self.write_timer:stop(loop)
		end
		self.io_write:stop(loop)
		self.io_read:stop(loop)
		sock:close()
		self.sock = nil
	end
end

local function sock_block_read(self, block)
	-- block/unblock read
	if block ~= self.read_blocked then
		self.read_blocked = block
		if block then
			self.io_read:stop(self.loop)
		else
			self.io_read:start(self.loop)
		end
	end
end

local function sock_handle_error(self, err)
	self.has_error = true -- mark socket as bad.
	sock_close(self)
	local handler = self.handler
	if handler then
		local errFunc = handler.handle_error
		if errFunc then
			errFunc(handler, err)
		else
			print('socket error:', err)
		end
	end
end

local function sock_set_write_timeout(self, timeout)
	local timer = self.write_timer
	-- default to no write timeout.
	timeout = timeout or -1
	self.write_timeout = timeout
	-- enable/disable timeout
	local is_disable = (timeout <= 0)
	-- create the write timer if one is needed.
	if not timer then
		-- don't create a disabled timer.
		if is_disable then return end
		timer = ev.Timer.new(function()
			sock_handle_error(self, 'write timeout')
		end, timeout, timeout)
		self.write_timer = timer
		-- enable timer if socket is write blocked.
		if self.write_blocked then
			timer:start(self.loop)
		end
		return
	end
	-- if the timer should be disabled.
	if is_disable then
		-- then disable the timer
		timer:stop(self.loop)
		return
	end
	-- update timeout interval and start the timer if socket is write blocked.
	if self.write_blocked then
		timer:again(self.loop, timeout)
	end
end

local function sock_reset_write_timeout(self)
	local timeout = self.write_timeout
	local timer = self.write_timer
	-- write timeout is disabled.
	if timeout < 0 or timer == nil then return end
	-- update timeout interval
	timer:again(self.loop, timeout)
end

local function sock_send_data(self, buf)
	local sock = self.sock
	local is_blocked = false

	local num, errno, err = sock:send(buf)
	if not num then
		-- got timeout error block writes.
		if num == false then
			-- got EAGAIN
			is_blocked = true
		else -- data == nil
			-- report error
			sock_handle_error(self, err)
			return nil, err
		end
	else
		-- trim sent data.
		if num < #buf then
			-- remove sent bytes from buffer.
			buf = buf:sub(num+1)
			-- partial send, not enough socket buffer space, so blcok writes.
			is_blocked = true
		else
			self.write_buf = nil
			if self.is_closing then
				-- write buffer is empty, finish closing socket.
				sock_close(self)
				return num, 'closed'
			end
		end
	end
	-- block/un-block write events.
	if is_blocked ~= self.write_blocked then
		self.write_blocked = is_blocked
		if is_blocked then
			self.write_buf = buf
			self.io_write:start(self.loop)
			-- socket is write blocked, start write timeout
			sock_reset_write_timeout(self)
			return num, 'blocked'
		else
			local loop = self.loop
			self.io_write:stop(loop)
			-- no data to write, so stop timer.
			if self.write_timer then
				self.write_timer:stop(loop)
			end
		end
	elseif is_blocked then
		-- reset write timeout, since some data was written and the socket is still write blocked.
		sock_reset_write_timeout(self)
	end
	return num
end

local function sock_send(self, data)
	-- only process send when given data to send.
	if data == nil or #data == 0 then return end
	local num, err
	local buf = self.write_buf
	if buf then
		buf = buf .. data
	else
		buf = data
	end
	if not self.write_blocked then
		num, err = sock_send_data(self, buf)
	else
		self.write_buf = buf
		-- let the caller know that the socket is blocked and data is being buffered
		err = 'blocked'
	end
	-- always return the size of the data passed in, since un-sent data will be buffered
	-- for sending later.
	return #data, err
end

local function sock_handle_connected(self)
	local handler = self.handler
	self.is_connecting = false
	if handler then
		local handle_connected = handler.handle_connected
		if handle_connected then
			handle_connected(handler)
		end
	end
end

local function sock_recv_data(self)
	local read_len = self.read_len
	local read_max = self.read_max
	local handler = self.handler
	local sock = self.sock
	local len = 0
	local is_connecting = self.is_connecting

	repeat
		local data, errno, err = sock:recv(read_len)
		if not data then
			if data == false then
				-- check if we where in the connecting state.
				if is_connecting then
					is_connecting = false
					sock_handle_connected(self)
				end
				-- no data
				return true
			else -- data == nil
				-- report error
				sock_handle_error(self, err)
				return false, err
			end
		end
		-- check if the other side shutdown there send stream
		if #data == 0 then
			-- report socket closed
			sock_handle_error(self, 'closed')
			return false, 'closed'
		end
		-- check if we where in the connecting state.
		if is_connecting then
			is_connecting = false
			sock_handle_connected(self)
		end
		-- pass read data to handler
		len = len + #data
		err = handler:handle_data(data)
		if err then
			-- report error
			sock_handle_error(self, err)
			return false, err
		end
	until len >= read_max or self.read_blocked

	return true
end

local function sock_sethandler(self, handler)
	self.handler = handler
	if handler and not self.is_connecting then
		-- raise 'connected' event for the new handler
		sock_handle_connected(self)
	end
end

local function sock_is_closed(self)
	return self.is_closing
end

local sock_mt = {
is_tls = false,
send = sock_send,
getsockopt = sock_getsockopt,
setsockopt = sock_setsockopt,
getsockname = sock_getsockname,
getpeername = sock_getpeername,
shutdown = sock_shutdown,
close = sock_close,
block_read = sock_block_read,
set_write_timeout = sock_set_write_timeout,
sethandler = sock_sethandler,
is_closed = sock_is_closed,
}
sock_mt.__index = sock_mt

local function sock_wrap(loop, handler, sock, is_connected)
	-- create socket object
	local self = {
		loop = loop,
		handler = handler,
		sock = sock,
		is_connecting = true,
		write_blocked = false,
		write_timeout = -1,
		read_blocked = false,
		read_len = 8192,
		read_max = 65536,
		is_closing = false,
	}
	setmetatable(self, sock_mt)

	-- make nixio socket non-blocking
	sock:setblocking(false)
	-- get socket FD
	local fd = sock:fileno()
	-- create callback closure
	local write_cb = function()
		local num, err = sock_send_data(self, self.write_buf)
		if self.write_buf == nil and not self.is_closing then
			-- write buffer is empty and socket is still open,
			-- call drain callback.
			local handler = self.handler
			local drain = handler.handle_drain
			if drain then
				local err = drain(handler)
				if err then
					-- report error
					sock_handle_error(self, err)
				end
			end
		end
	end
	local read_cb = function()
		sock_recv_data(self)
	end

	-- create IO watchers.
	if is_connected then
		self.io_write = ev.IO.new(write_cb, fd, ev.WRITE)
		self.is_connecting = false
	else
		local connected_cb = function(loop, io, revents)
			if not self.write_blocked then
				io:stop(loop)
			end
			-- change callback to write_cb
			io:callback(write_cb)
			-- check for connect errors by tring to read from the socket.
			sock_recv_data(self)
		end
		self.io_write = ev.IO.new(connected_cb, fd, ev.WRITE)
		self.io_write:start(loop)
	end
	self.io_read = ev.IO.new(read_cb, fd, ev.READ)
	self.io_read:start(loop)

	return self
end

local function sock_new_connect(loop, handler, domain, _type, host, port, laddr, lport)
	-- create nixio socket
	local sock = new_socket(domain, _type)
	-- wrap socket
	local self = sock_wrap(loop, handler, sock)
	-- bind to local laddr/lport
	if laddr then
		n_assert(sock:setsockopt('socket', 'reuseaddr', 1))
		n_assert(sock:bind(laddr, tonumber(lport or 0)))
	end
	-- connect to host:port
	local ret, errno, err = sock:connect(host, port)
	if not ret and errno ~= EINPROGRESS then
		-- report error
		sock_handle_error(self, err)
		return nil, err
	end
	return self
end

-- remove '[]' from IPv6 addresses
local function strip_ipv6(ip6)
	if ip6 and ip6:sub(1,1) == '[' then
		return ip6:sub(2,-2)
	end
	return ip6
end

module(...)

--
-- TCP/UDP/Unix sockets (non-tls)
--
function tcp6(loop, handler, host, port, laddr, lport)
	host = strip_ipv6(host)
	laddr = strip_ipv6(laddr)
	return sock_new_connect(loop, handler, 'inet6', 'stream', host, port, laddr, lport)
end

function tcp(loop, handler, host, port, laddr, lport)
	if host:sub(1,1) == '[' then
		return tcp6(loop, handler, host, port, laddr, lport)
	else
		return sock_new_connect(loop, handler, 'inet', 'stream', host, port, laddr, lport)
	end
end

function udp6(loop, handler, host, port, laddr, lport)
	host = strip_ipv6(host)
	laddr = strip_ipv6(laddr)
	return sock_new_connect(loop, handler, 'inet6', 'dgram', host, port, laddr, lport)
end

function udp(loop, handler, host, port, laddr, lport)
	if host:sub(1,1) == '[' then
		return udp6(loop, handler, host, port, laddr, lport)
	else
		return sock_new_connect(loop, handler, 'inet', 'dgram', host, port, laddr, lport)
	end
end

function unix(loop, handler, path)
	return sock_new_connect(loop, handler, 'unix', 'stream', path)
end

function wrap_connected(loop, handler, sock)
	-- wrap socket
	return sock_wrap(loop, handler, sock, true)
end

--
-- TCP TLS sockets
--
function tls_tcp(loop, handler, host, port, tls, is_client, laddr, lport)
	local self = tcp(loop, handler, host, port, laddr, lport)
	-- default to client-side TLS
	if is_client == nil then is_client = true end
	return sock_tls_wrap(self, tls, is_client)
end

function tls_tcp6(loop, handler, host, port, tls, is_client, laddr, lport)
	local self = tcp6(loop, handler, host, port, laddr, lport)
	-- default to client-side TLS
	if is_client == nil then is_client = true end
	return sock_tls_wrap(self, tls, is_client)
end

function tls_wrap_connected(loop, handler, sock, tls, is_client)
	-- wrap socket
	local self = sock_wrap(loop, handler, sock, false)
	-- default to server-side TLS
	if is_client == nil then is_client = false end
	return sock_tls_wrap(self, tls, is_client)
end

--
-- URI
--
function uri(loop, handler, uri)
	local orig_uri = uri
	-- parse uri
	uri = uri_parse(uri)
	local scheme = uri.scheme
	assert(scheme, "Invalid listen URI: " .. orig_uri)
	local q = query_parse(uri.query)
	-- use scheme to select socket type.
	if scheme == 'unix' then
		return unix(loop, handler, uri.path)
	else
		local host, port = uri.host, uri.port or default_port
		if scheme == 'tcp' then
			return tcp(loop, handler, host, port, q.laddr, q.lport)
		elseif scheme == 'tcp6' then
			return tcp6(loop, handler, host, port, q.laddr, q.lport)
		elseif scheme == 'udp' then
			return udp(loop, handler, host, port, q.laddr, q.lport)
		elseif scheme == 'udp6' then
			return udp6(loop, handler, host, port, q.laddr, q.lport)
		else
			local mode = q.mode or 'client'
			local is_client = (mode == 'client')
			-- default to client-side
			-- create TLS context
			local tls = nixio.tls(mode)
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
				return tls_tcp(loop, handler, host, port, tls, is_client, q.laddr, q.lport)
			elseif scheme == 'tls6' then
				return tls_tcp6(loop, handler, host, port, tls, is_client, q.laddr, q.lport)
			end
		end
	end
	error("Unknown listen URI scheme: " .. scheme)
end

-- export
wrap = sock_wrap

