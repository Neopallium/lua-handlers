-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local zsocket = require'handler.zsocket'
local ev = require'ev'
local loop = ev.Loop.default
local socket = require'socket'

local ctx = zsocket.new(loop, 1)

local function get_next_job(sock, last_job_response)
	-- send job request
	assert(sock:send({last_job_response}))
end

-- define response handler
function handle_msg(sock, data)
  print("got job:\n", data)
	-- DO WORK
	socket.sleep(1)
	-- get next job
	get_next_job(sock, 'echo job:' .. data)
end

-- create PAIR worker
local zreq = ctx:req(handle_msg)

math.randomseed(os.time())
zreq:identity(string.format("<req:%x>",math.floor(1000 * math.random())))
zreq:connect("tcp://localhost:5555")

-- get first job
get_next_job(zreq, '')

loop:loop()

