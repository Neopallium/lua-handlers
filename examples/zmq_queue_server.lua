-- Copyright (c) 2010-2011 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local zmq = require'handler.zmq'
local ev = require'ev'
local loop = ev.Loop.default

local ctx = zmq.init(loop, 1)

local tinsert = table.insert
local tremove = table.remove
local work_requests = {}

--[[
TODO:
* should have job pull & job results messages that the workers can send, that way
  workers can send the jobs results, then exit or do after job clean-up work before
	requesting next job
]]

-- define request handler
local function handle_msg(sock, msg)
print('server:', unpack(msg))
	local addr = {}
	-- get address parts of message
	for i=1,#msg do
		local part = msg[i]
		addr[i] = part
		if part == '' then break end
	end
	-- queue work request
print('server: queue worker address:', unpack(addr))
	tinsert(work_requests, addr)
end

-- create response worker
local zxrep = ctx:xrep(handle_msg)

zxrep:identity("<xrep>")
zxrep:bind("tcp://lo:5555")

local function io_in_cb()
	-- get job
	local line = io.read("*l")
	-- send job to first queued worker
	local addr = tremove(work_requests)
	if addr then
		-- add job to message address
		tinsert(addr, line)
		zxrep:send(addr)
	else
		print('WARNING: no workers waiting for jobs.  TODO: implement job wait queue.')
	end
end
local io_in = ev.IO.new(io_in_cb, 0, ev.READ)
io_in:start(loop)

-- create PUB socket for broadcast of status.
local zpub = ctx:pub()
zpub:bind("tcp://lo:5556")

-- use server start time to allow workers to detect server restarts.
-- TODO: use a better time source or a true random number source
local start_time = tostring(os.time())

local function status_update_cb()
	zpub:send(start_time)
end
local status_update = ev.Timer.new(status_update_cb, 1.0, 1.0)
status_update:start(loop)

loop:loop()

