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

local nsocket_mt = {
handle_error = function(this, loc, err)
	local worker = this.worker
	local errFunc = worker.handle_error
	this.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(worker, loc, err)
	else
		print('nsocket: ' .. loc .. ': error ', err)
	end
	this:close()
end,
send = function(this, data)
	local num, err
	local buf = this.write_buf
	if buf then
		this.write_buf = buf .. data
	else
		this.write_buf = data
	end
	if not this.write_blocked then
		num, err = this:_send_data()
	end
	return #data, err
end,
_send_data = function(this)
	local sock = this.socket
	local buf = this.write_buf
	local is_blocked = false

	local num, err = sock:send(buf)
	if num then
		-- trim sent data.
		if num < #buf then
			this.write_buf = buf:sub(num+1)
			-- partial send, not enough socket buffer space, so blcok writes.
			is_blocked = true
		else
			this.write_buf = nil
			if this.is_closing then
				-- write buffer is empty, finish closing socket.
				this:close()
			end
		end
	else
		-- got timeout error block writes.
		if err == 'timeout' then
			is_blocked = true
		else
			-- socket error
			this:handle_error('send', err)
			return nil, err
		end
	end
	-- block/un-block write events.
	if is_blocked ~= this.write_blocked then
		this.write_blocked = is_blocked
		if is_blocked then
			this.io_write:start(this.loop)
			return num, 'blocked'
		else
			this.io_write:stop(this.loop)
		end
	end
	return num
end,
_receive_data = function(this)
	local read_len = this.read_len
	local read_max = this.read_max
	local worker = this.worker
	local sock = this.socket
	local len = 0

	repeat
		local data, err, part = sock:receive(read_len)
		if err and err ~= 'timeout' then
			-- socket error
			this:handle_error('receive', err)
			return false, err
		end
		-- check for partial read
		if err == 'timeout' then
			-- check for partial data.
			if part and #part > 0 then
				data = part
			else
				-- no data
				return true
			end
		end
		-- pass read data to worker
		len = len + #data
		err = worker:handle_data(data)
		if err then
			-- worker error
			this:handle_error('worker', err)
			return false, err
		end
	until len >= read_max

	return true
end,
getstats = function(this)
	return this.socket:getstats()
end,
getsockname = function(this)
	return this.socket:getsockname()
end,
setoption = function(this, ...)
	return this.socket:setoption(...)
end,
close = function(this)
	this.is_closing = true
	if not this.write_buf or this.has_error then
		this.io_write:stop(this.loop)
		this.io_read:stop(this.loop)
		this.socket:close()
	end
end,
}
nsocket_mt.__index = nsocket_mt

local function nsocket_wrap(loop, worker, sck)
	-- create nsocket
	local this = {
		loop = loop,
		worker = worker,
		socket = sck,
		write_blocked = false,
		read_len = 8192,
		read_max = 65536,
		is_closing = false,
	}
	setmetatable(this, nsocket_mt)

	sck:settimeout(0)
	local fd = sck:getfd()
	-- create callback closure
	local write_cb = function()
		this:_send_data()
	end
	local read_cb = function()
		this:_receive_data()
	end
	local connected_cb = function(loop, io, revents)
		if not this.write_blocked then
			io:stop(loop)
		end
		-- check for connect errors
		-- TODO: Need to call 'handle_connected' callback before 'handle_data' callback.
		local ret, err = this:_receive_data()
		if ret then
			local handle_connected = worker.handle_connected
			if handle_connected then
				handle_connected(worker)
			end
			-- change callback to write_cb
			io:callback(write_cb)
		end
	end
	-- create IO watcher.
	this.io_write = ev.IO.new(connected_cb, fd, ev.WRITE)
	this.io_read = ev.IO.new(read_cb, fd, ev.READ)

	--this.io_write:start(loop)
	this.io_read:start(loop)

	return this
end

module'handler.nsocket'

function new(loop, worker, host, port)
	-- connect to server.
	local sck = socket.tcp()
	local this = nsocket_wrap(loop, worker, sck)
	local ret, err = sck:connect(host, port)
	if err and err ~= 'timeout' then
		-- socket error
		this:handle_error('connect', err)
		return nil, err
	end
	return this
end

-- export
wrap = nsocket_wrap

