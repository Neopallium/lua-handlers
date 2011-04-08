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

local connection = require'handler.connection'
local ev = require'ev'
local loop = ev.Loop.default

local io_in

local generic_client_mt = {
handle_error = function(self, err)
	print('client.error:', err)
	io_in:stop(loop)
end,
handle_connected = function(self)
	print('client.connected: sending hello message to server')
	-- say hi
	self.sock:send('hello from client connected to: ' .. self.uri)
end,
handle_data = function(self, data)
	print('from server: ' .. data)
end,
send = function(self, data)
	self.sock:send(data)
end,
}
generic_client_mt.__index = generic_client_mt

-- new generic client
local function new_generic_client(uri)
	print('Connecting to: ' .. uri)
	local self = setmetatable({ uri = uri }, generic_client_mt)
	self.sock = connection.uri(loop, self, uri)
	return self
end

local uri = arg[1] or 'tcp://localhost:8081/'
local count = tonumber(arg[2] or 1)
local clients = {}

for i=1,count do
	clients[i] = new_generic_client(uri)
end

local function client_send(...)
	for i=1,count do
		clients[i]:send(...)
	end
end

local function io_in_cb()
	local line = io.read("*l")
	if line and #line > 0 then
		client_send(line)
	end
end
io_in = ev.IO.new(io_in_cb, 0, ev.READ)
io_in:start(loop)

loop:loop()

