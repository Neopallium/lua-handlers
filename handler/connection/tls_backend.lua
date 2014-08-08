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

local nixio = require"nixio"

local ev = require"ev"

-- important SSL error codes
local SSL_ERROR_SSL = 1
local SSL_ERROR_WANT_READ = 2
local SSL_ERROR_WANT_WRITE = 3
local SSL_ERROR_WANT_X509_LOOKUP = 4
local SSL_ERROR_SYSCALL = 5
local SSL_ERROR_ZERO_RETURN = 6
local SSL_ERROR_WANT_CONNECT = 7
local SSL_ERROR_WANT_ACCEPT = 8

local function sock_setsockopt(self, level, option, value)
	return self.sock.socket:setsockopt(level, option, value)
end

local function sock_getsockopt(self, level, option)
	return self.sock.socket:getsockopt(level, option)
end

local function sock_getpeername(self)
	return self.sock.socket:getpeername()
end

local function sock_getsockname(self)
	return self.sock.socket:getsockname()
end

local function sock_shutdown(self, read, write)
	if read then
		-- stop reading from socket, we don't want any more data.
		self.io_read:stop(self.loop)
	end
end

local function sock_close(self)
	self.is_closing = true
	if not self.write_buf or self.has_error then
		local loop = self.loop
		if self.write_timer then
			self.write_timer:stop(loop)
		end
		self.io_write:stop(loop)
		self.io_read:stop(loop)
		self.sock:shutdown()
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

local function sock_handle_error(self, err, errno)
	local handler = self.handler
	local errFunc = handler and handler.handle_error
	self.has_error = true -- mark socket as bad.
	sock_close(self)
	if err == nil then
		if errno == SSL_ERROR_SYSCALL then
			errno = nixio.errno()
		end
		err = 'TLS error code: ' .. tostring(errno)
	end
	if errFunc then
		errFunc(handler, err)
	else
		print('socket error:', err)
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
			sock_handle_error(self, err, errno)
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
			elseif errno ~= SSL_ERROR_WANT_READ then
				-- report error
				sock_handle_error(self, err, errno)
				return false, err
			end
			-- no data
			return true
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
	until len >= read_max and not self.read_blocked or self.shutdown_waiting

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

local function sock_handshake(self, is_client)
	local stat, code
	if is_client then
		stat, code = self.sock:connect()
	else
		stat, code = self.sock:accept()
	end
	if stat then
		self.is_handshake_complete = true
		return true, code
	else
		self.is_handshake_complete = false
		return false, code
	end
end

local tls_sock_mt = {
is_tls = true,
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
tls_sock_mt.__index = tls_sock_mt

local function sock_tls_wrap(self, tls, is_client)
	local loop = self.loop
	-- create TLS context
	tls = tls or nixio.tls(is_client and 'client' or 'server')
	-- convertion normal socket to TLS
	setmetatable(self, tls_sock_mt)
	self.sock = tls:create(self.sock)

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

	-- create callback for TLS handshake
	self.is_handshake_complete = false
	-- block writes until handshake is completed, to force queueing of sent data.
	self.write_blocked = true
	self.read_blocked = false -- no need to block reads.
	local handshake_cb = function()
		local is_handshake_complete, code = sock_handshake(self, is_client)
		if is_handshake_complete then
			self.write_blocked = false
			self.io_write:stop(loop)
			-- install normal read/write callbacks
			self.io_write:callback(write_cb)
			self.io_read:callback(read_cb)
			-- check if we where in the connecting state.
			if self.is_connecting then
				sock_handle_connected(self)
			end
			-- check for pending write data.
			local buf = self.write_buf
			if buf then
				sock_send_data(self, buf)
			end
		else
			if code == SSL_ERROR_WANT_WRITE then
				self.io_write:start(loop)
			elseif code == SSL_ERROR_WANT_READ then
				self.io_write:stop(loop)
			else
				-- report error
				sock_handle_error(self, "SSL_Error: code=" .. code)
			end
		end
	end
	self.io_write:callback(handshake_cb)
	self.io_read:callback(handshake_cb)
	-- start TLS handshake
	handshake_cb()

	-- always keep read events enabled.
	self.io_read:start(loop)

	return self
end

module(...)

-- export
wrap = sock_tls_wrap

