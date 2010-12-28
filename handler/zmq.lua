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
local tinsert = table.insert
local tremove = table.remove

local ev = require"ev"
local zmq = require"zmq"
local z_SUBSCRIBE = zmq.SUBSCRIBE
local z_UNSUBSCRIBE = zmq.UNSUBSCRIBE
local z_IDENTITY = zmq.IDENTITY
local z_NOBLOCK = zmq.NOBLOCK
local z_RCVMORE = zmq.RCVMORE
local z_SNDMORE = zmq.SNDMORE

local mark_SNDMORE = {}

local default_send_max = 10
local default_recv_max = 10

local function zsock_getopt(self, ...)
	return self.socket:getopt(...)
end

local function zsock_setopt(self, ...)
	return self.socket:setopt(...)
end

local function zsock_sub(self, filter)
	return self.socket:setopt(z_SUBSCRIBE, filter)
end

local function zsock_unsub(self, filter)
	return self.socket:setopt(z_UNSUBSCRIBE, filter)
end

local function zsock_identity(self, filter)
	return self.socket:setopt(z_IDENTITY, filter)
end

local function zsock_bind(self, ...)
	return self.socket:bind(...)
end

local function zsock_connect(self, ...)
	return self.socket:connect(...)
end

local function zsock_close(self)
	self.is_closing = true
	if #self.send_queue == 0 or self.has_error then
		self.io_send:stop(self.loop)
		self.io_recv:stop(self.loop)
		self.io_idle:stop(self.loop)
		self.socket:close()
	end
end

local function zsock_handle_error(self, err)
	local handler = self.handler
	local errFunc = handler.handle_error
	self.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(self, err)
	else
		print('zmq socket: error ', err)
	end
	zsock_close(self)
end

local function zsock_enable_idle(self, enable)
	if enable == self.idle_enabled then return end
	self.idle_enabled = enable
	if enable then
		self.io_idle:start(self.loop)
	else
		self.io_idle:stop(self.loop)
	end
end

local function zsock_send_data(self)
	local send_max = self.send_max
	local count = 0
	local s = self.socket
	local queue = self.send_queue

	repeat
		local data = queue[1]
		local flags = 0
		-- check for send more marker
		if queue[2] == mark_SNDMORE then
			flags = z_SNDMORE
		end
		local sent, err = s:send(data, flags + z_NOBLOCK)
		if not sent then
			-- got timeout error block writes.
			if err == 'timeout' then
				-- enable write IO callback.
				self.send_enabled = false
				if not self.send_blocked then
					self.io_send:start(self.loop)
					self.send_blocked = true
				end
			else
				-- report error
				zsock_handle_error(self, err)
			end
			return
		else
			-- pop sent data from queue
			tremove(queue, 1)
			-- pop send more marker
			if flags == z_SNDMORE then
				tremove(queue, 1)
			else
				-- finished whole message.
				if self._has_state then
					-- switch to receiving state.
					self.state = "RECV_ONLY"
					self.recv_enabled = true
					-- make sure idle watcher is running.
					zsock_enable_idle(self, true)
				end
			end
			-- check if queue is empty
			if #queue == 0 then
				self.send_enabled = false
				if self.send_blocked then
					self.io_send:stop(self.loop)
					self.send_blocked = false
				end
				-- finished queue is empty
				return
			end
		end
		count = count + 1
	until count >= send_max
	-- hit max send and still have more data to send
	self.send_enabled = true
	-- make sure idle watcher is running.
	zsock_enable_idle(self, true)
	return
end

local function zsock_receive_data(self)
	local recv_max = self.recv_max
	local count = 0
	local s = self.socket
	local handler = self.handler
	local msg = self.recv_msg
	self.recv_msg = nil

	repeat
    local data, err = s:recv(z_NOBLOCK)
		if err then
			-- check for blocking.
			if err == 'timeout' then
				-- check if we received a partial message.
				self.recv_msg = msg
				-- recv blocked
				self.recv_enabled = false
				if not self.recv_blocked then
					self.io_recv:start(self.loop)
					self.recv_blocked = true
				end
			else
				-- report error
				zsock_handle_error(self, err)
			end
			return
		end
		-- check for more message parts.
		local more = s:getopt(z_RCVMORE)
		if msg ~= nil then
			tinsert(msg, data)
		else
			if more == 1 then
				-- create multipart message
				msg = { data }
			else
				-- simple one part message
				msg = data
			end
		end
		if more == 0 then
			-- finished receiving whole message
			if self._has_state then
				-- switch to sending state.
				self.state = "SEND_ONLY"
			end
			-- pass read message to handler
			err = handler.handle_msg(self, msg)
			if err then
				-- report error
				zsock_handle_error(self, err)
				return
			end
			-- we are finished if the state is stil SEND_ONLY
			if self._has_state and self.state == "SEND_ONLY" then
				self.recv_enabled = false
				return
			end
			msg = nil
		end
		count = count + 1
	until count >= recv_max

	-- save any partial message.
	self.recv_msg = msg

	-- hit max receive and we are not blocked on receiving.
	self.recv_enabled = true
	-- make sure idle watcher is running.
	zsock_enable_idle(self, true)

end

local function _queue_msg(queue, msg)
	local parts = #msg
	-- queue first part of message
	tinsert(queue, msg[1])
	for i=2,parts do
		-- queue more marker flag
		tinsert(queue, mark_SNDMORE)
		-- queue part of message
		tinsert(queue, msg[i])
	end
end

local function zsock_send(self, data, more)
	local queue = self.send_queue
	-- check if we are in receiving-only state.
	if self._has_state and self.state == "RECV_ONLY" then
		return false, "Can't send when in receiving state."
	end
	if type(data) == 'table' then
		-- queue multipart message
		_queue_msg(queue, data)
	else
		-- queue simple data.
		tinsert(queue, data)
	end
	-- check if there is more data to send
	if more then
		-- queue a marker flag
		tinsert(queue, mark_SNDMORE)
	end
	-- try sending data now.
	if not self.send_blocked then
		zsock_send_data(self)
	end
	return true, nil
end

local function zsock_handle_idle(self)
	if self.recv_enabled then
		zsock_receive_data(self)
	end
	if self.send_enabled then
		zsock_send_data(self)
	end
	if not self.send_enabled and not self.recv_enabled then
		zsock_enable_idle(self, false)
	end
end

local zsock_mt = {
_has_state = false,
send = zsock_send,
setopt = zsock_setopt,
getopt = zsock_getopt,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_mt.__index = zsock_mt

local zsock_no_send_mt = {
_has_state = false,
setopt = zsock_setopt,
getopt = zsock_getopt,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_no_send_mt.__index = zsock_no_send_mt

local zsock_sub_mt = {
_has_state = false,
setopt = zsock_setopt,
getopt = zsock_getopt,
sub = zsock_sub,
unsub = zsock_unsub,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_sub_mt.__index = zsock_sub_mt

local zsock_state_mt = {
_has_state = true,
send = zsock_send,
setopt = zsock_setopt,
getopt = zsock_getopt,
identity = zsock_identity,
bind = zsock_bind,
connect = zsock_connect,
close = zsock_close,
}
zsock_state_mt.__index = zsock_state_mt

local type_info = {
	-- publish/subscribe sockets
	[zmq.PUB]  = { mt = zsock_mt, enable_recv = false, recv = false, send = true },
	[zmq.SUB]  = { mt = zsock_sub_mt, enable_recv = true,  recv = true, send = false },
	-- push/pull sockets
	[zmq.PUSH] = { mt = zsock_mt, enable_recv = false, recv = false, send = true },
	[zmq.PULL] = { mt = zsock_no_send_mt, enable_recv = true,  recv = true, send = false },
	-- two-way pair socket
	[zmq.PAIR] = { mt = zsock_mt, enable_recv = true,  recv = true, send = true },
	-- request/response sockets
	[zmq.REQ]  = { mt = zsock_state_mt, enable_recv = false, recv = true, send = true },
	[zmq.REP]  = { mt = zsock_state_mt, enable_recv = true,  recv = true, send = true },
	-- extended request/response sockets
	[zmq.XREQ] = { mt = zsock_mt, enable_recv = true, recv = true, send = true },
	[zmq.XREP] = { mt = zsock_mt, enable_recv = true,  recv = true, send = true },
}

local function zsock_wrap(s, s_type, loop, msg_cb, err_cb)
	local tinfo = type_info[s_type]
	handler = { handle_msg = msg_cb, handle_error = err_cb}
	-- create zmq socket
	local self = {
		s_type = x_type,
		socket = s,
		loop = loop,
		handler = handler,
		send_enabled = false,
		recv_enabled = false,
		idle_enabled = false,
		is_closing = false,
	}
	setmetatable(self, tinfo.mt)

	local fd = s:getopt(zmq.FD)
	-- create IO watcher.
	if tinfo.send then
		local send_cb = function()
			-- try sending data.
			zsock_send_data(self)
		end
		self.io_send = ev.IO.new(send_cb, fd, ev.WRITE)
		self.send_blocked = false
		self.send_queue = {}
		self.send_max = default_send_max
	end
	if tinfo.recv then
		local recv_cb = function()
			-- try receiving data.
			zsock_receive_data(self)
		end
		self.io_recv = ev.IO.new(recv_cb, fd, ev.READ)
		self.recv_blocked = false
		self.recv_max = default_recv_max
		if tinfo.enable_recv then
			self.io_recv:start(loop)
		end
	end
	local idle_cb = function()
		zsock_handle_idle(self)
	end
	-- this Idle watcher is used to convert ZeroMQ FD's edge-triggered fashion to level-triggered
	self.io_idle = ev.Idle.new(idle_cb)

	return self
end

local function create(self, s_type, msg_cb, err_cb)
	-- create ZeroMQ socket
	local s, err = self.ctx:socket(s_type)
	if not s then return nil, err end

	-- wrap socket.
	return zsock_wrap(s, s_type, self.loop, msg_cb, err_cb)
end

module'handler.zmq'

local meta = {}
meta.__index = meta
local function no_recv_cb()
	error("Invalid this type of ZeroMQ socket shouldn't receive data.")
end
function meta:pub(err_cb)
	return create(self, zmq.PUB, no_recv_cb, err_cb)
end

function meta:sub(msg_cb, err_cb)
	return create(self, zmq.SUB, msg_cb, err_cb)
end

function meta:push(err_cb)
	return create(self, zmq.PUSH, no_recv_cb, err_cb)
end

function meta:pull(msg_cb, err_cb)
	return create(self, zmq.PULL, msg_cb, err_cb)
end

function meta:pair(msg_cb, err_cb)
	return create(self, zmq.PAIR, msg_cb, err_cb)
end

function meta:req(msg_cb, err_cb)
	return create(self, zmq.REQ, msg_cb, err_cb)
end

function meta:rep(msg_cb, err_cb)
	return create(self, zmq.REP, msg_cb, err_cb)
end

function meta:xreq(msg_cb, err_cb)
	return create(self, zmq.XREQ, msg_cb, err_cb)
end

function meta:xrep(msg_cb, err_cb)
	return create(self, zmq.XREP, msg_cb, err_cb)
end

function meta:term()
	return self.ctx:term()
end

function init(loop, io_threads)
	-- create ZeroMQ context
	local ctx, err = zmq.init(io_threads)
	if not ctx then return nil, err end

	return setmetatable({ ctx = ctx, loop = loop }, meta)
end

