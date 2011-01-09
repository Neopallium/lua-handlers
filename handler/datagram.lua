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

local socket = require"socket"
local ev = require"ev"

local function udp_setsockname(self, ...)
	return self.socket:setsockname(...)
end

local function udp_getsockname(self)
	return self.socket:getsockname()
end

local function udp_setpeername(self, ...)
	return self.peeret:setpeername(...)
end

local function udp_getpeername(self)
	return self.peeret:getpeername()
end

local function udp_setoption(self, ...)
	return self.socket:setoption(...)
end

local function udp_close(self)
	self.io_read:stop(self.loop)
	self.socket:close()
end

local function udp_handle_error(self, err)
	local handler = self.handler
	local errFunc = handler.handle_error
	self.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(handler, err)
	else
		print('udp socket error:', err)
	end
	udp_close(self)
end

local function udp_sendto(self, data, ip, port)
	return self.socket:sendto(data, ip, port)
end

local function udp_receive_data(self)
	local max_packet = self.max_packet
	local read_max = self.read_max
	local handler = self.handler
	local sock = self.socket
	local len = 0

	repeat
		local data, ip, port = sock:receivefrom(max_packet)
		if data == nil then
			if ip == 'timeout' then
				-- no data
				return true
			else
				-- socket error
				udp_handle_error(self, ip)
				return false, ip
			end
		end
		-- pass read data to handler
		local err = handler:handle_data(data, ip, port)
		if err then
			-- report error
			udp_handle_error(self, err)
			return false, err
		end
		len = len + #data
	until len >= read_max

	return true
end

local udp_mt = {
sendto = udp_sendto,
getsockname = udp_getsockname,
setsockname = udp_setsockname,
getpeername = udp_getpeername,
setpeername = udp_setpeername,
setoption = udp_setoption,
close = udp_close,
}
udp_mt.__index = udp_mt

local function udp_wrap(loop, handler, sck)
	-- create udp socket object
	local self = {
		loop = loop,
		handler = handler,
		socket = sck,
		max_packet = 8192,
		read_max = 65536,
	}
	setmetatable(self, udp_mt)

	sck:settimeout(0)
	local fd = sck:getfd()

	-- create callback closure
	local read_cb = function()
		udp_receive_data(self)
	end
	-- create IO watcher.
	self.io_read = ev.IO.new(read_cb, fd, ev.READ)

	self.io_read:start(loop)

	return self
end

module'handler.datagram'

function new(loop, handler, host, port)
	-- connect to server.
	local sck = socket.udp()
	assert(sck:setsockname(host, port))
	return udp_wrap(loop, handler, sck)
end

-- export
wrap = udp_wrap

