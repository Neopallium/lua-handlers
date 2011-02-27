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
	printf("usage: %s <bind-to> <message-size> <message-count>", arg[0])
	os.exit()
end

local bind_to = arg[1]
local message_size = tonumber(arg[2])
local message_count = tonumber(arg[3])

local socket = require'socket'
local time = socket.gettime
local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default

local ctx = zmq.init(loop, 1)

local start_time, end_time
local i = 0
-- define SUB worker
local function handle_msg(sock, data)
	if i == 0 then
		start_time = time()
	end
	i = i + 1
	if i == message_count then
		end_time = time()
		loop:unloop()
	end
end

-- create SUB worker
local zsub = ctx:sub(handle_msg)

zsub.recv_max = 200000 --math.max(message_count / 1000, 20)
zsub:sub("")
zsub:bind(bind_to)

loop:loop()

local elapsed = end_time - start_time
if elapsed == 0 then
	elapsed = 1
end

printf("elapsed: %d secs", elapsed)
local throughput = message_count / elapsed
local megabits = throughput * message_size * 8 / 1000000

printf("message size: %d [B]", message_size)
printf("message count: %d", message_count)
printf("mean throughput: %d [msg/s]", throughput)
printf("mean throughput: %.3f [Mb/s]", megabits)

zsub:close()
ctx:term()

