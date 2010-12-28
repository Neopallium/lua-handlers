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

local socket = require"socket"
local ev = require"ev"

local function tcp_getstats(self)
	return self.socket:getstats()
end

local function tcp_setstats(self, ...)
	return self.socket:setstats(...)
end

local function tcp_getsockname(self)
	return self.socket:getsockname()
end

local function tcp_setoption(self, ...)
	return self.socket:setoption(...)
end

local function tcp_close(self)
	self.is_closing = true
	if not self.write_buf or self.has_error then
		self.io_write:stop(self.loop)
		self.io_read:stop(self.loop)
		self.socket:close()
	end
end

local function tcp_handle_error(self, err)
	local handler = self.handler
	local errFunc = handler.handle_error
	self.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(handler, err)
	else
		print('tcp socket error:', err)
	end
	tcp_close(self)
end

local function tcp_send_data(self, buf)
	local sock = self.socket
	local is_blocked = false

	local num, err, part = sock:send(buf)
	num = num or part
	if num then
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
				tcp_close(self)
				return num, 'closed'
			end
		end
	else
		-- got timeout error block writes.
		if err == 'timeout' then
			is_blocked = true
		else
			-- report error
			tcp_handle_error(self, err)
			return nil, err
		end
	end
	-- block/un-block write events.
	if is_blocked ~= self.write_blocked then
		self.write_blocked = is_blocked
		if is_blocked then
			self.write_buf = buf
			self.io_write:start(self.loop)
			return num, 'blocked'
		else
			self.io_write:stop(self.loop)
		end
	end
	return num
end

local function tcp_send(self, data)
	local num, err
	local buf = self.write_buf
	if buf then
		buf = buf .. data
	else
		buf = data
	end
	if not self.write_blocked then
		num, err = tcp_send_data(self, buf)
	else
		-- let the caller know that the socket is blocked and data is being buffered
		err = 'blocked'
	end
	-- always return the size of the data passed in, since un-sent data will be buffered
	-- for sending later.
	return #data, err
end

local function tcp_handle_connected(self)
	local handler = self.handler
	self.is_connecting = false
	local handle_connected = handler.handle_connected
	if handle_connected then
		handle_connected(handler)
	end
end

local function tcp_receive_data(self)
	local read_len = self.read_len
	local read_max = self.read_max
	local handler = self.handler
	local sock = self.socket
	local len = 0
	local is_connecting = self.is_connecting

	repeat
		local data, err, part = sock:receive(read_len)
		if part and #part > 0 then
			-- only got partial data.
			data = part
		elseif not data then
			if err == 'timeout' then
				-- check if we where in the connecting state.
				if is_connecting then
					is_connecting = false
					tcp_handle_connected(self)
				end
				-- no data
				return true
			else
				-- report error
				tcp_handle_error(self, err)
				return false, err
			end
		end
		-- check if we where in the connecting state.
		if is_connecting then
			is_connecting = false
			tcp_handle_connected(self)
		end
		-- pass read data to handler
		len = len + #data
		err = handler:handle_data(data)
		if err then
			-- report error
			tcp_handle_error(self, err)
			return false, err
		end
	until len >= read_max

	return true
end

local tcp_mt = {
send = tcp_send,
getstats = tcp_getstats,
setstats = tcp_setstats,
getsockname = tcp_getsockname,
setoption = tcp_setoption,
close = tcp_close,
}
tcp_mt.__index = tcp_mt

local function tcp_wrap(loop, handler, sck)
	-- create tcp socket object
	local self = {
		loop = loop,
		handler = handler,
		socket = sck,
		is_connecting = true,
		write_blocked = false,
		read_len = 8192,
		read_max = 65536,
		is_closing = false,
	}
	setmetatable(self, tcp_mt)

	sck:settimeout(0)
	local fd = sck:getfd()
	-- create callback closure
	local write_cb = function()
		local num, err = tcp_send_data(self, self.write_buf)
		if self.write_buf == nil and not self.is_closed then
			-- write buffer is empty and socket is still open,
			-- call drain callback.
			local handler = self.handler
			local drain = handler.handle_drain
			if drain then
				local err = drain(handler)
				if err then
					-- report error
					tcp_handle_error(self, err)
				end
			end
		end
	end
	local read_cb = function()
		tcp_receive_data(self)
	end
	local connected_cb = function(loop, io, revents)
		if not self.write_blocked then
			io:stop(loop)
		end
		-- change callback to write_cb
		io:callback(write_cb)
		-- check for connect errors by tring to read from the socket.
		tcp_receive_data(self)
	end
	-- create IO watcher.
	self.io_write = ev.IO.new(connected_cb, fd, ev.WRITE)
	self.io_read = ev.IO.new(read_cb, fd, ev.READ)

	self.io_write:start(loop)
	self.io_read:start(loop)

	return self
end

module'handler.tcp'

function new(loop, handler, host, port)
	-- connect to server.
	local sck = socket.tcp()
	local self = tcp_wrap(loop, handler, sck)
	local ret, err = sck:connect(host, port)
	if err and err ~= 'timeout' then
		-- report error
		tcp_handle_error(self, err)
		return nil, err
	end
	return self
end

-- export
wrap = tcp_wrap

