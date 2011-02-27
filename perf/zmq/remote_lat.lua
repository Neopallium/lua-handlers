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
	printf("usage: %s <connect-to> <message-size> <roundtrip-count>", arg[0])
	os.exit()
end

local connect_to = arg[1]
local message_size = tonumber(arg[2])
local roundtrip_count = tonumber(arg[3])

local socket = require'socket'
local time = socket.gettime
local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default

local ctx = zmq.init(loop, 1)

local msg = string.rep('0', message_size)
local start_time, end_time
local i = 0
-- define request handler
local function handle_msg(sock, data)
	i = i + 1
	if i == roundtrip_count then
		end_time = time()
		loop:unloop()
		return
	end
	sock:send(msg)
end

-- create response worker
local zreq = ctx:req(handle_msg)

zreq:connect(connect_to)

start_time = time()
-- send first message
zreq:send(msg)

loop:loop()

local elapsed = end_time - start_time

local latency = elapsed * 1000000 / roundtrip_count / 2

printf("message size: %d [B]", message_size)
printf("roundtrip count: %d", roundtrip_count)
printf("mean latency: %.3f [us]", latency)

zreq:close()
ctx:term()

