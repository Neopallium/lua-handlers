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

local acceptor = require'handler.acceptor'
local ev = require'ev'
local loop = ev.Loop.default

local tcp_client_mt = {
handle_error = function(self, err)
	print('tcp_client.error:', self, err)
	self.timer:stop(loop)
end,
handle_connected = function(self)
	print('tcp_client.connected:', self)
end,
handle_data = function(self, data)
	print('tcp_client.data:', self, data)
end,
handle_timer = function(self)
	self.sock:send('ping\n')
end,
}
tcp_client_mt.__index = tcp_client_mt

-- new tcp client
local function new_tcp_client(sock)
print('new_tcp_client:', sock)
	local self = setmetatable({ sock = sock }, tcp_client_mt)
	sock:sethandler(self)

	-- create timer watcher
	self.timer = ev.Timer.new(function()
		self:handle_timer()
	end, 1.0, 1.0)
	self.timer:start(loop)
	return self
end

-- new tcp server
local function new_server(port, handler, tls)
	print('New tcp server listen on: ' .. port)
	if tls then
		return acceptor.tls_tcp(loop, handler, '*', port, tls, 1024)
	else
		return acceptor.tcp(loop, handler, '*', port, 1024)
	end
end

local port = arg[1] or 4081
local key = arg[2] or 'examples/localhost.key'
local cert = arg[3] or 'examples/localhost.cert'

-- create server-side TLS Context.
local tls = nixio.tls'server'
assert(tls:set_key(key))
assert(tls:set_cert(cert))

local server = new_server(port, new_tcp_client, tls)

loop:loop()

