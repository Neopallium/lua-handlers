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

local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default
local socket = require'socket'

local ctx = zmq.init(loop, 1)

local function get_next_job(sock, last_job_response)
	-- send job request
print('send job request')
	assert(sock:send({last_job_response}))
end

-- define response handler
local function handle_job(sock, data)
  print("got job:\n", data)
	-- DO WORK
	socket.sleep(1)
	-- get next job
	get_next_job(sock, 'echo job:' .. data)
end

-- create socket for requesting jobs
local zreq = nil
math.randomseed(os.time())

local function start_request_socket()
	-- close old socket
	if zreq then
		print('closing old request socket.')
		zreq:close()
	end

	print('connect request socket to queue server.')
	zreq = ctx:req(handle_job)

	zreq:identity(string.format("<req:%x>",math.floor(100000 * math.random())))
	zreq:connect("tcp://localhost:5555")

	-- request first job.
	get_next_job(zreq, '')
end

local queue_start_time = nil
-- subscribe to queue server to detect server restarts.
local function handle_sub(sock, data)
	if not queue_start_time then
		print('Got first queue start time message.')
		-- we just started so this is our first message from the server.
		-- so store the server's start time.
		queue_start_time = data
		-- and connect request socket.
		start_request_socket()
	elseif queue_start_time ~= data then
		print('Got NEW queue start time message, queue server must have restarted.')
		-- detected different queue server, the old one must have died.
		queue_start_time = data
		-- and re-connect request socket.
		start_request_socket()
	end
end

-- subscribe to queue server
local zsub = ctx:sub(handle_sub)

zsub:sub("")
zsub:connect("tcp://localhost:5556")

loop:loop()

