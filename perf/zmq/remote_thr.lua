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
	printf("usage: %s <connect-to> <message-size> <message-count>", arg[0])
	os.exit()
end

local connect_to = arg[1]
local message_size = tonumber(arg[2])
local message_count = tonumber(arg[3])

local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default

local ctx = zmq.init(loop, 1)

-- create PUB worker
local zpub = ctx:pub()

zpub.send_max = 200 --math.max(message_count / 1000, 20)
zpub:connect(connect_to)

local msg = string.rep('0', message_size)
for i=1,message_count do
	zpub:send(msg)
end

local timer = ev.Timer.new(function()
	loop:unloop()
end, 1)
timer:start(loop, true)

loop:loop()

zpub:close()
ctx:term()

