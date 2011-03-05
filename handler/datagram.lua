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

local ev = require"ev"
local nixio = require"nixio"
local new_socket = nixio.socket

local function dgram_setsockopt(self, level, option, value)
	return self.sock:setsockopt(level, option, value)
end

local function dgram_getsockopt(self, level, option)
	return self.sock:getsockopt(level, option)
end

local function dgram_setsockname(self, addr, port)
	return self.sock:setsockname(addr, port)
end

local function dgram_getsockname(self)
	return self.sock:getsockname()
end

local function dgram_setpeername(self, addr, port)
	return self.sock:setpeername(addr, port)
end

local function dgram_getpeername(self)
	return self.sock:getpeername()
end

local function dgram_close(self)
	self.io_read:stop(self.loop)
	self.sock:close()
end

local function dgram_handle_error(self, err)
	local handler = self.handler
	local errFunc = handler.handle_error
	self.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(handler, err)
	else
		print('udp socket error:', err)
	end
	dgram_close(self)
end

local function dgram_sendto(self, data, ip, port)
	return self.sock:sendto(data, ip, port)
end

local function dgram_recvfrom_data(self)
	local max_packet = self.max_packet
	local read_max = self.read_max
	local handler = self.handler
	local sock = self.sock
	local len = 0
	local err

	repeat
		local data, ip, port = sock:recvfrom(max_packet)
		if not data then
			if data == false then
				-- no data
				return true
			else
				err = port
				-- report error
				dgram_handle_error(self, err)
				return false, err
			end
		end
		-- check if the other side shutdown there send stream
		if #data == 0 then
			-- report socket closed
			dgram_handle_error(self, 'closed')
			return false, 'closed'
		end
		-- pass read data to handler
		err = handler:handle_data(data, ip, port)
		if err then
			-- report error
			dgram_handle_error(self, err)
			return false, err
		end
		len = len + #data
	until len >= read_max

	return true
end

local dgram_mt = {
sendto = dgram_sendto,
getsockopt = dgram_getsockopt,
setsockopt = dgram_setsockopt,
getsockname = dgram_getsockname,
setsockname = dgram_setsockname,
getpeername = dgram_getpeername,
setpeername = dgram_setpeername,
close = dgram_close,
}
dgram_mt.__index = dgram_mt

local function dgram_wrap(loop, handler, sock)
	-- create udp socket object
	local self = {
		loop = loop,
		handler = handler,
		sock = sock,
		max_packet = 8192,
		read_max = 65536,
	}
	setmetatable(self, dgram_mt)

	-- make nixio socket non-blocking
	sock:setblocking(false)
	-- get socket FD
	local fd = sock:fileno()

	-- create callback closure
	local read_cb = function()
		dgram_recvfrom_data(self)
	end
	-- create IO watcher.
	self.io_read = ev.IO.new(read_cb, fd, ev.READ)

	self.io_read:start(loop)

	return self
end

local function dgram_new_bind(loop, handler, domain, host, port)
	-- nixio uses nil to mena any local address
	if host == '*' then host = nil end
	-- create nixio socket
	local sock = new_socket(domain, 'dgram')
	-- wrap socket
	local self = dgram_wrap(loop, handler, sock)
	-- connect to host:port
	local ret, errno, err = sock:bind(host, port)
	if not ret then
		-- report error
		dgram_handle_error(self, err)
		return nil, err
	end
	return self
end

module(...)

function udp(loop, handler, host, port)
	return dgram_new_bind(loop, handler, 'inet', host, port)
end

-- default datagram type to udp.
new = udp

function udp6(loop, handler, host, port)
	return dgram_new_bind(loop, handler, 'inet6', host, port)
end

function unix(loop, handler, path)
	return dgram_new_bind(loop, handler, 'unix', path)
end

