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

local connection = require"handler.connection"

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
	local sock = self.sock
	if sock then
		self.sock = nil
		sock:close()
		if self.parser then
			self.parser:reset()
		end
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

function conn_mt:handle_error(err)
	conn_raise_error(self, err)
	-- close connection on all errors.
	self:close()
end

local function reply_on_complete(reply)
	local conn = reply.connection
	-- handle reply
	call_callback(conn, 'on_reply', reply)
	return true
end

local BUF_LEN = 512
local socks_tmp_buf = new_buffer(BUF_LEN)

local function handle_replies(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local status, err = self.reply:parse(buf)
	if not status and not err then
		conn_raise_error(self, err)
	end
end

local function client_on_connected(self)
	-- Login Success
	self.handle_data = handle_replies
	-- handle connected
	call_callback(self, 'on_connected')
end

local function handle_user_pass(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local status, err = self.user_pass:parse(buf)
	if status then
		if self.user_pass.status == 0 then
			client_on_connected(self)
		else
			conn_raise_error(self, "Invalid username/password.")
		end
	elseif not status and not err then
		conn_raise_error(self, err)
	end
end

local function handle_method(self, data)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(data)
	local status, err = self.method:parse(buf)
	if status then
		local method = self.method.method
		if method == 0 then
			-- No authentication required.
			self.handle_data = handle_replies
		elseif method == 2 then
			-- Require username/password
			self:send_user_pass()
			self.handle_data = handle_user_pass
		else
			conn_raise_error(self, "No Acceptable method")
		end
		-- handle method
		call_callback(self, 'on_method', self.method.method)
	elseif err then
		conn_raise_error(self, err)
	end
end

function conn_mt:send_request(request)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode request
	assert(request:encode(buf))

	-- send reply
	self.sock:send(buf:tostring())
end

function conn_mt:send_user_pass()
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode username/password request.
	user_pass.encode_request(buf, self.username, self.password)

	-- send request
	self.sock:send(buf:tostring())
end

local function conn_send_methods(self)
	local buf = socks_tmp_buf
	buf:reset() -- clear old data.

	-- encode methods list
	methods.encode_methods(buf, self.methods)

	-- send methods
	self.sock:send(buf:tostring())
end

function conn_mt:handle_connected()
	-- send methods list to server
	conn_send_methods(self)
end

module(...)

function new(uri, self)
	self = setmetatable(self, conn_mt)

	self.handle_data = handle_method

	-- connect to SOCKS server
	local sock, err = connection.uri(self, uri)
	if sock == nil then return nil, err end
	self.sock = sock

	-- set socket read_len
	sock.read_len = BUF_LEN

	-- create reply parser
	self.reply = request_reply.new_reply({
		on_complete = reply_on_complete,
		connection = self,
	})
	-- create request encoder
	self.request = request_reply.new_request()

	-- create method parser
	self.method = methods.new_method()

	-- create user_pass parser
	self.user_pass = user_pass.new_reply()

	-- Authentication methods.
	self.methods = {}
	if self.username and self.password then
		self.methods[1] = 2
	else
		self.methods[1] = 0
	end

	return self
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

