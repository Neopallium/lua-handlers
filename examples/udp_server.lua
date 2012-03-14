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

local handler = require'handler'
local poll = handler.get_poller()
local acceptor = require'handler.acceptor'

local udp_client_mt = {
handle_error = function(self, err)
	print('udp_client.error:', self, err)
	self.timer:stop()
end,
handle_connected = function(self)
	print('udp_client.connected:', self)
end,
handle_data = function(self, data)
	print('udp_client.data:', self, data)
end,
handle_timer = function(self)
	self.sock:send('ping\n')
end,
}
udp_client_mt.__index = udp_client_mt

-- new udp client
local function new_udp_client(sock)
print('new_udp_client:', sock)
	local self = setmetatable({}, udp_client_mt)
	sock:sethandler(self)
	self.sock = sock

	-- create timer watcher
	self.timer = poll:create_timer(self, 1.0, 1.0)
	self.timer:start()
	return self
end

-- new udp server
local function new_server(port, handler)
	print('New udp server listen on: ' .. port)
	return acceptor.udp(handler, '*', port, 1024)
end

local port = arg[1] or 8081
local server = new_server(port, new_udp_client)

handler.run()

