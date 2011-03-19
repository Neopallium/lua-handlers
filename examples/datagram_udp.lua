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

local datagram = require'handler.datagram'
local ev = require'ev'
local loop = ev.Loop.default

local udp_client_mt = {
handle_error = function(self, err)
	if err ~= 'closed' then
		print('udp_client.error:', err)
	end
end,
handle_data = function(self, data, ip, port)
	print('udp_client.data:',data, ip, port)
	self.sock:sendto('hello\n', ip, port)
end,
}
udp_client_mt.__index = udp_client_mt

-- new udp client
local function new_udp_client(host, port)
	local self = setmetatable({}, udp_client_mt)
	self.sock = datagram.new(loop, self, host, port)
	return self
end

local host = arg[1] or "*"
local port = arg[2] or 8081
local client = new_udp_client(host, port)

loop:loop()

