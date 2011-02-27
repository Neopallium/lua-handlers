-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, replish, distribute, sublicense, and/or sell
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

local format = string.format
local function printf(fmt, ...)
	print(format(fmt, ...))
end

if #arg ~= 3 then
	printf("usage: %s <bind-to> <message-size> <roundtrip-count>", arg[0])
	os.exit()
end

local bind_to = arg[1]
local message_size = tonumber(arg[2])
local roundtrip_count = tonumber(arg[3])
 
local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default

local ctx = zmq.init(loop, 1)

local i = 0
-- define request handler
local function handle_msg(sock, data)
	sock:send(data)
	i = i + 1
	if i == roundtrip_count then
		loop:unloop()
	end
end

-- create response worker
local zrep = ctx:rep(handle_msg)

zrep.recv_max = 1000
zrep:bind(bind_to)

loop:loop()

zrep:close()
ctx:term()

