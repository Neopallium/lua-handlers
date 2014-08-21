-- Copyright (c) 2014 by Robert G. Jakabosky <bobby@neoawareness.com>
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
local assert = assert

local handler = require"handler"
local poll = handler.get_poller()

local new_buffer = require"handler.buffer".new

local request_reply = require"handler.socks.request_reply"
local methods = require"handler.socks.methods"
local user_pass = require"handler.socks.auth.user_pass"

local function call_callback(obj, cb, ...)
	local meth_cb = obj[cb]
	if meth_cb then
		return meth_cb(obj, ...)
	end
	return false
end

local conn_mt = {}
conn_mt.__index = conn_mt

function conn_mt:close()
	self.is_closed = true
	local sock = self.sock
	if sock then
		self.sock = nil
		-- kill timer.
		self.timer:stop()
		sock:close()
		if self.parser then
			self.parser:reset()
		end
		self.server:remove_connection(self)
	end
end

local function conn_raise_error(self, err)
	-- signal an error
	call_callback(self, 'on_error', err)
end

function conn_mt:on_error(err)
	print("SOCKS error:", err)
	self:close()
end

local function conn_set_next_timeout(self, timeout, reason)
	local timer = self.timer
	if timeout < 0 then
		-- disable timer
		timer:stop()
		return
	end
	-- change timer's timeout and start it.
	timer:again(timeout)
	self.timeout_reason = reason
end

function conn_mt:on_timer(timer)
	-- disable timer
	timer:stop()
	-- raise error with timeout reason.
	conn_raise_error(self, self.timeout_reason or 'timeout')
	-- shutdown Socks connection
	self:close()
end

function conn_mt:handle_error(err)
	conn_raise_error(self, err)
	-- close connection on all errors.
	self:close()
end

local function request_on_complete(request)
	local conn = request.connection
	-- handle request
	call_callback(conn.server, 'on_request', request, conn.reply, conn)
	return true
end

local BUF_LEN = 512
local socks_tmp_buf = new_buffer(BUF_LEN)

local function handle_requests(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local state, err = self.request:parse(buf)
	if not state and not err then
		conn_raise_error(self, err)
	end
end

local function handle_user_pass(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local state, err = self.user_pass:parse(buf)
	if state then
		-- check user/pass
		if self.server:check_user(self.user_pass.user, self.user_pass.pass) then
			self:send_user_pass(0) -- Success
		else
			self:send_user_pass(1) -- Failed
			self:close()
		end
		-- change data handler
		self.handle_data = handle_requests
	elseif not state and not err then
		conn_raise_error(self, err)
	end
end

local function handle_methods(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local state, err = self.methods:parse(buf)
	if state then
		-- handle methods
		call_callback(self.server, 'on_methods', self.methods, self)
		-- select method
		local method = self.server:select_method(self.methods) or 0xFF
		-- send method
		self:send_method(method)
		-- change data handler
		if method == 0 then
			self.handle_data = handle_requests
		elseif method == 2 then
			self.handle_data = handle_user_pass
		else
			-- unsupported method.
			self:close()
		end
	elseif err then
		conn_raise_error(self, err)
	end
end

function conn_mt:send_reply(reply)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode reply
	assert(reply:encode(buf))

	-- send reply
	self.sock:send(buf:tostring())

	return self:reply_complete()
end

function conn_mt:send_method(method)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode method reply
	methods.encode_method(buf, method or 0xFF)

	-- send reply
	self.sock:send(buf:tostring())
end

function conn_mt:send_user_pass(status)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode user/pass reply
	user_pass.encode_reply(buf, status)

	-- send reply
	self.sock:send(buf:tostring())
end

function conn_mt:reply_complete()
	-- then start keep-alive idle timeout
	conn_set_next_timeout(self, self.keep_alive_timeout, "keep-alive timeout")
end

module(...)

function new(server, sock)
	local self = setmetatable({
		sock = sock,
		server = server,
		is_closed = false,
		handle_data = handle_methods,
		-- copy timeouts from server
		auth_timeout = server.auth_timeout or -1,
		keep_alive_timeout = server.keep_alive_timeout or -1,
		max_requests = server.max_keep_alive_requests or 0,
	}, conn_mt)

	-- set socket read_len
	sock.read_len = BUF_LEN

	-- create request parser
	self.request = request_reply.new_request({
		on_complete = request_on_complete,
		connection = self,
	})
	-- create reply encoder
	self.reply = request_reply.new_reply()

	-- create methods parser
	self.methods = methods.new_methods()

	-- create user/pass parser
	self.user_pass = user_pass.new_request()

	-- create connection timer.
	self.timer = poll:create_timer(self, 1, 1)

	-- set this Socks connection object as the socket's handler.
	sock:sethandler(self)

	-- start timeout
	conn_set_next_timeout(self, self.auth_timeout, "Authentication timed out.")
	return self
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

