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

local handler = require"handler"
local poll = handler.get_poller()

local uv = require"luv"

local WRITE_HIGH = 256 * 1024
local WRITE_LOW  = 8 * 1024

--local tls_backend = require"handler.connection.tls_backend"
--local sock_tls_wrap = tls_backend.wrap

local uri_mod = require"handler.uri"
local uri_parse = uri_mod.parse
local query_parse = uri_mod.parse_query

local function n_assert(test, errno, msg)
	return assert(test, msg)
end

local function sock_fileno(self)
	return self.sock:fileno()
end

local function sock_setsockopt(self, level, option, value)
	error('not implemented yet')
end

local function sock_getsockopt(self, level, option)
	error('not implemented yet')
end

local function sock_getpeername(self)
	return self.sock:getpeername()
end

local function sock_getsockname(self)
	return self.sock:getsockname()
end

local function sock_shutdown(self, read, write)
	if read then
		-- stop reading from socket, we don't want any more data.
		self.sock:read_stop()
	elseif write then
		return self.sock:shutdown()
	end
end

local function sock_write_pending(self)
	return self.sock:write_queue_size() > 0
end

local function sock_close(self)
	local sock = self.sock
	if not sock then return end
	self.is_closing = true
	self.read_blocked = true
	if not sock_write_pending(self) or self.has_error then
		if self.write_timer then
			self.write_timer:stop()
		end
		sock:close()
		self.sock = nil
	else
		-- Stil sending data, shutdown read-side.
		sock_shutdown(self, true, false)
	end
end

local function sock_block_read(self, block)
	-- block/unblock read
	if block ~= self.read_blocked then
		self.read_blocked = block
		if block then
			self.sock:read_stop()
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

local function sock_on_timer(self, timer)
	sock_handle_error(self, 'write timeout')
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
		timer = poll:create_timer(self, timeout, timeout)
		self.write_timer = timer
		-- enable timer if socket is write blocked.
		if sock_write_pending(self) then
			timer:start()
		end
		return
	end
	-- if the timer should be disabled.
	if is_disable then
		-- then disable the timer
		timer:stop()
		return
	end
	-- update timeout interval and start the timer if socket is write blocked.
	if sock_write_pending(self) then
		timer:again(timeout)
	end
end

local function sock_reset_write_timeout(self)
	local timeout = self.write_timeout
	local timer = self.write_timer
	-- write timeout is disabled.
	if timeout < 0 or timer == nil then return end
	-- update timeout interval
	timer:again(timeout)
end

local function sock_handle_send_unblocked(self)
	-- no data to write, so stop timer.
	if self.write_timer then
		self.write_timer:stop()
	end
end

local function sock_send(self, data)
	local num, err, errno = self.sock:write(data, self.on_io_write)
	if not num then
		return false, errno
	end
	local write_size = self.sock:write_queue_size()
	if write_size > WRITE_HIGH and self.write_size < WRITE_HIGH then
		self.write_size = write_size
		sock_reset_write_timeout(self)
		return false, 'blocked'
	end
	return true
end

local function sock_handle_connected(self)
	-- skip if not in connecting state.
	if not self.is_connecting then return end
	local handler = self.handler
	self.is_connecting = false
	if handler then
		local handle_connected = handler.handle_connected
		if handle_connected then
			handle_connected(handler)
		end
	end
end

local function sock_read_cb(self, err, data)
	if not data then
		-- report error
		sock_handle_error(self, err)
		return
	end
	-- check if the other side shutdown there send stream
	local len = #data
	-- pass read data to handler
	err = self.handler:handle_data(data)
	if err then
		-- report error
		sock_handle_error(self, err)
		return
	end
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
fileno = sock_fileno,
getsockopt = sock_getsockopt,
setsockopt = sock_setsockopt,
getsockname = sock_getsockname,
getpeername = sock_getpeername,
shutdown = sock_shutdown,
close = sock_close,
block_read = sock_block_read,
on_timer = sock_on_timer,
set_write_timeout = sock_set_write_timeout,
sethandler = sock_sethandler,
is_closed = sock_is_closed,
}
sock_mt.__index = sock_mt

local function sock_write_cb(self, status)
	-- make sure sock is still open.
	if not self.sock then return end

	local write_size = self.sock:write_queue_size()

	if write_size < WRITE_HIGH then
		-- some data written reset write timeout.
		sock_reset_write_timeout(self)
	end

	if write_size > WRITE_LOW then
		-- writes still blocked.
		return
	end
	-- writes unblocked.
	sock_handle_send_unblocked(self)
	if not self.is_closing then
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

local function sock_connected_cb(self, status)
	-- make sure sock is still open.
	if not self.sock then return end

	-- socket is now connected.
	sock_handle_connected(self)

	-- start reading from socket.
	self.sock:read_start(function(err, data)
		return sock_read_cb(self, err, data)
	end)
end

local function sock_wrap(handler, sock, is_connected)
	-- create socket object
	local self = {
		handler = handler,
		sock = sock,
		is_connecting = true,
		write_size = 0,
		write_timeout = -1,
		read_blocked = false,
		read_len = 8192,
		read_max = 65536,
		is_closing = false,
	}
	setmetatable(self, sock_mt)

	-- make socket non-blocking
	--sock:setblocking(false)

	-- create IO watchers.
	self.on_io_write_cb = function(status)
		return sock_write_cb(self, status)
	end
	if is_connected then
		-- already connected don't need to call connected callback.
		self.is_connecting = false
		sock_connected_cb(self, status)
	end

	return self
end

local function sock_new_connect(handler, domain, _type, host, port, laddr, lport)
	-- create nixio socket
	local sock
	if _type == 'stream' then
		sock = uv.new_tcp()
	else
		sock = uv.new_udp()
	end
	-- wrap socket
	local self = sock_wrap(handler, sock)
	-- bind to local laddr/lport
	if laddr then
		--n_assert(sock:setsockopt('socket', 'reuseaddr', 1))
		n_assert(sock:bind(laddr, tonumber(lport or 0)))
	end
	-- connect to host:port
	local ret, err, errno = sock:connect(host, port, function(status)
		return sock_connected_cb(self, status)
	end)
	if not ret and errno ~= "EINPROGRESS" then
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
function tcp6(handler, host, port, laddr, lport)
	host = strip_ipv6(host)
	laddr = strip_ipv6(laddr)
	return sock_new_connect(handler, 'inet6', 'stream', host, port, laddr, lport)
end

function tcp(handler, host, port, laddr, lport)
	if host:sub(1,1) == '[' then
		return tcp6(handler, host, port, laddr, lport)
	else
		return sock_new_connect(handler, 'inet', 'stream', host, port, laddr, lport)
	end
end

function udp6(handler, host, port, laddr, lport)
	error('Not implemented yet')
	host = strip_ipv6(host)
	laddr = strip_ipv6(laddr)
	return sock_new_connect(handler, 'inet6', 'dgram', host, port, laddr, lport)
end

function udp(handler, host, port, laddr, lport)
	error('Not implemented yet')
	if host:sub(1,1) == '[' then
		return udp6(handler, host, port, laddr, lport)
	else
		return sock_new_connect(handler, 'inet', 'dgram', host, port, laddr, lport)
	end
end

function unix(handler, path)
	return sock_new_connect(handler, 'unix', 'stream', path)
end

function wrap_connected(handler, sock)
	-- wrap socket
	return sock_wrap(handler, sock, true)
end

--
-- TCP TLS sockets
--
function tls_tcp(handler, host, port, tls, is_client, laddr, lport)
	error('Not implemented yet')
	local self = tcp(handler, host, port, laddr, lport)
	-- default to client-side TLS
	if is_client == nil then is_client = true end
	return sock_tls_wrap(self, tls, is_client)
end

function tls_tcp6(handler, host, port, tls, is_client, laddr, lport)
	error('Not implemented yet')
	local self = tcp6(handler, host, port, laddr, lport)
	-- default to client-side TLS
	if is_client == nil then is_client = true end
	return sock_tls_wrap(self, tls, is_client)
end

function tls_wrap_connected(handler, sock, tls, is_client)
	error('Not implemented yet')
	-- wrap socket
	local self = sock_wrap(handler, sock, false)
	-- default to server-side TLS
	if is_client == nil then is_client = false end
	return sock_tls_wrap(self, tls, is_client)
end

--
-- URI
--
function uri(handler, uri)
	local orig_uri = uri
	-- parse uri
	uri = uri_parse(uri)
	local scheme = uri.scheme
	assert(scheme, "Invalid listen URI: " .. orig_uri)
	local q = query_parse(uri.query)
	-- use scheme to select socket type.
	if scheme == 'unix' then
		return unix(handler, uri.path)
	else
		local host, port = uri.host, uri.port or default_port
		if scheme == 'tcp' then
			return tcp(handler, host, port, q.laddr, q.lport)
		elseif scheme == 'tcp6' then
			return tcp6(handler, host, port, q.laddr, q.lport)
		elseif scheme == 'udp' then
			return udp(handler, host, port, q.laddr, q.lport)
		elseif scheme == 'udp6' then
			return udp6(handler, host, port, q.laddr, q.lport)
		else
			local mode = q.mode or 'client'
			local is_client = (mode == 'client')
			-- default to client-side
			-- create TLS context
			error('Not implemented yet')
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
				return tls_tcp(handler, host, port, tls, is_client, q.laddr, q.lport)
			elseif scheme == 'tls6' then
				return tls_tcp6(handler, host, port, tls, is_client, q.laddr, q.lport)
			end
		end
	end
	error("Unknown listen URI scheme: " .. scheme)
end

-- export
wrap = sock_wrap

