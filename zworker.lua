local setmetatable = setmetatable
local print = print
local tinsert = table.insert
local tremove = table.remove

local ev = require"ev"
local zmq = require"zmq"

local default_send_max = 2
local default_recv_max = 2

local function worker_getopt(this, ...)
	return this.socket:getopt(...)
end

local function worker_setopt(this, ...)
	return this.socket:setopt(...)
end

local function worker_bind(this, ...)
	return this.socket:bind(...)
end

local function worker_connect(this, ...)
	return this.socket:connect(...)
end

local function worker_close(this)
	this.is_closing = true
	if #this.send_queue == 0 or this.has_error then
		this.io_send:stop(this.loop)
		this.io_recv:stop(this.loop)
		this.io_idle:stop(this.loop)
		this.socket:close()
	end
end

local function worker_handle_error(this, loc, err)
	local worker = this.worker
	local errFunc = worker.handle_error
	this.has_error = true -- mark socket as bad.
	if errFunc then
		errFunc(this, loc, err)
	else
		print('zworker: ' .. loc .. ': error ', err)
	end
	worker_close(this)
end

local function worker_send_data(this)
	local send_max = this.send_max
	local count = 0
	local s = this.socket
	local buf = this.send_queue

	repeat
		local data = buf[1]
		local sent, err = s:send(data, zmq.NOBLOCK)
		if not sent then
			-- got timeout error block writes.
			if err == 'timeout' then
				-- enable write IO callback.
				if not this.send_blocked then
					this.io_send:start(this.loop)
					this.send_blocked = true
					this.send_enabled = false
				end
			else
				-- socket error
				worker_handle_error(this, 'send', err)
			end
			return false, err
		else
			-- pop sent data from queue
			tremove(buf, 1)
			-- check if queue is empty
			if #buf == 0 then
				this.send_blocked = false
				this.send_enabled = false
				break;
			end
		end
		count = count + 1
	until count >= send_max
	return true
end

local function worker_enable_receive(this, enable)
	if enable then
		if not this.recv_blocked then
			this.recv_enabled = false
			if not this.idle_enabled then
				this.io_idle:start(this.loop)
				this.idle_enabled = true
			end
		end
	else
		if this.recv_blocked then
			this.io_recv:stop(this.loop)
			this.recv_blocked = false
		end
		this.recv_enabled = false
	end
end

local function worker_receive_data(this)
	local recv_max = this.recv_max
	local count = 0
	local s = this.socket
	local worker = this.worker
	local buf = this.recv_part
	this.recv_part = ''

	repeat
    local data, err = s:recv(zmq.NOBLOCK)
		if err then
			-- check for blocking.
			if err == 'timeout' then
				-- check if we received a partial message.
				if s:getopt(zmq.RCVMORE) == 1 then
					this.recv_part = buf
				end
				-- recv blocked
				if not this.recv_blocked then
					this.io_recv:start(this.loop)
					this.recv_blocked = true
					this.recv_enabled = false
				end
			else
				-- socket error
				worker_handle_error(this, 'receive', err)
			end
			return false, err
		end
		-- handle data.
		buf = buf .. data
		if s:getopt(zmq.RCVMORE) == 0 then
			-- pass read data to worker
			err = worker.handle_data(this, buf)
			if err then
				-- worker error
				worker_handle_error(this, 'worker', err)
				return false, err
			end
			buf = ''
		end
		count = count + 1
	until count >= recv_max

	return true
end

local function worker_send(this, data, multipart)
	local buf = this.send_queue
	local part = this.send_part
	-- check if we already have a partial message to send
	if part then
		-- pre-append partial data to new data.
		data = part .. data
		this.send_part = nil
	end
	-- check if there is more data to send
	if multipart then
		-- don't put partial message data into send queue.
		this.send_part = data
		-- TODO: improve handling of multipart messages.
		return true
	else
		-- got full message add to send queue
		tinsert(buf, data)
	end
	if not this.send_blocked then
		return worker_send_data(this)
	end
	return true
end

local function worker_handle_idle(this)
	if this.send_enabled then
		worker_send_data(this)
	end
	if this.recv_enabled then
		worker_receive_data(this)
	end
	if not this.send_enabled and not this.recv_enabled then
		this.idle_enabled = false
		this.io_idle:stop(this.loop)
	end
end

local zworker_mt = {
send = worker_send,
setopt = worker_setopt,
getopt = worker_getopt,
bind = worker_bind,
connect = worker_connect,
close = worker_close,
}
zworker_mt.__index = zworker_mt

local zworker_no_send_mt = {
setopt = worker_setopt,
getopt = worker_getopt,
bind = worker_bind,
connect = worker_connect,
close = worker_close,
}
zworker_no_send_mt.__index = zworker_no_send_mt

-- TODO: fix req/rep
local zworker_req_mt = {
send = worker_send,
setopt = worker_setopt,
getopt = worker_getopt,
bind = worker_bind,
connect = worker_connect,
close = worker_close,
}
zworker_req_mt.__index = zworker_req_mt

local zworker_rep_mt = {
send = worker_send,
setopt = worker_setopt,
getopt = worker_getopt,
bind = worker_bind,
connect = worker_connect,
close = worker_close,
}
zworker_rep_mt.__index = zworker_rep_mt

local type_info = {
	-- simple fixed state workers
	[zmq.PUB]  = { mt = zworker_mt, enable_recv = false, recv = false, send = true },
	[zmq.SUB]  = { mt = zworker_no_send_mt, enable_recv = true,  recv = true, send = false },
	[zmq.PUSH] = { mt = zworker_mt, enable_recv = false, recv = false, send = true },
	[zmq.PULL] = { mt = zworker_no_send_mt, enable_recv = true,  recv = true, send = false },
	[zmq.PAIR] = { mt = zworker_mt, enable_recv = true,  recv = true, send = true },
	-- request/response workers
	[zmq.REQ]  = { mt = zworker_req_mt, enable_recv = false, recv = true, send = true },
	[zmq.REP]  = { mt = zworker_rep_mt, enable_recv = true,  recv = true, send = true },
	[zmq.XREQ] = { mt = zworker_req_mt, enable_recv = false, recv = true, send = true },
	[zmq.XREP] = { mt = zworker_rep_mt, enable_recv = true,  recv = true, send = true },
}

local function zworker_wrap(s, s_type, loop, data_cb, err_cb)
	local tinfo = type_info[s_type]
	worker = { handle_data = data_cb, handle_error = err_cb}
	-- create zworker
	local this = {
		s_type = x_type,
		socket = s,
		loop = loop,
		worker = worker,
		send_enabled = false,
		recv_enabled = false,
		idle_enabled = false,
		is_closing = false,
	}
	setmetatable(this, tinfo.mt)

	local fd = s:getopt(zmq.FD)
	-- create IO watcher.
	if tinfo.send then
		local send_cb = function()
			this.send_enabled = true
			this.io_send:stop(this.loop)
			this.send_blocked = false
			if not this.idle_enabled then
				this.io_idle:start(this.loop)
				this.idle_enabled = true
			end
		end
		this.io_send = ev.IO.new(send_cb, fd, ev.WRITE)
		this.send_blocked = false
		this.send_queue = {}
		this.send_max = default_send_max
	end
	if tinfo.recv then
		local recv_cb = function()
			this.recv_enabled = true
			this.io_recv:stop(this.loop)
			this.recv_blocked = false
			if not this.idle_enabled then
				this.io_idle:start(this.loop)
				this.idle_enabled = true
			end
		end
		this.io_recv = ev.IO.new(recv_cb, fd, ev.READ)
		this.recv_blocked = false
		this.recv_part = ''
		this.recv_max = default_recv_max
		if tinfo.enable_recv then
			this.io_recv:start(loop)
		end
	end
	local idle_cb = function()
		worker_handle_idle(this)
	end
	-- create Idle watcher
	-- this is used to convert ZeroMQ FD's edge-triggered fashion to level-triggered
	this.io_idle = ev.Idle.new(idle_cb)

	return this
end

module(...)

function new(ctx, s_type, loop, data_cb, err_cb)
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, data_cb, err_cb)
end

local function no_recv_cb()
	error("Invalid this type of ZeroMQ socket shouldn't receive data.")
end
function new_pub(ctx, loop)
	local s_type = zmq.PUB
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, no_recv_cb)
end

function new_sub(ctx, loop, data_cb, err_cb)
	local s_type = zmq.SUB
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, data_cb, err_cb)
end

function new_push(ctx, loop)
	local s_type = zmq.PUSH
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, no_recv_cb)
end

function new_pull(ctx, loop, data_cb, err_cb)
	local s_type = zmq.PULL
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, data_cb, err_cb)
end

function new_pair(ctx, loop, data_cb, err_cb)
	local s_type = zmq.PAIR
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, data_cb, err_cb)
end

function new_req(ctx, loop, response_cb, err_cb)
	local s_type = zmq.REQ
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, response_cb, err_cb)
end

function new_rep(ctx, loop, request_cb, err_cb)
	local s_type = zmq.REP
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, request_cb, err_cb)
end

function new_xreq(ctx, loop, response_cb, err_cb)
	local s_type = zmq.XREQ
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, response_cb, err_cb)
end

function new_xrep(ctx, loop, request_cb, err_cb)
	local s_type = zmq.XREP
	local s = ctx:socket(s_type)
	return zworker_wrap(s, s_type, loop, request_cb, err_cb)
end

function wrap(s, loop, data_cb, err_cb)
	local s_type = s:getopt(zmq.TYPE)
	return zworker_wrap(s, s_type, loop, data_cb, err_cb)
end

