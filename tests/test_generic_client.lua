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

local generic_client_mt = {
handle_error = function(self, err)
	print('generic_client.error:', err)
end,
handle_connected = function(self)
	print('generic_client.connected')
end,
handle_data = function(self, data)
	print('generic_client.data:', data)
end,
}
generic_client_mt.__index = generic_client_mt

-- new generic client
local function new_generic_client(uri)
	print('Connecting to: ' .. uri)
	local self = setmetatable({}, generic_client_mt)
	self.sck = connection.uri(loop, self, uri)
	return self
end

local uri = arg[1] or 'tcp://localhost:8081/'
local client = new_generic_client(uri)

loop:loop()

