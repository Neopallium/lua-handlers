-- Copyright (c) 2011 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local backend = 'llnet'

local start_port = 1080
local end_port = 1080
local backlog = 8192
local family = 'inet'

local i=1
while i <= #arg do
	local p = arg[i]
	if p == '-p' then
		i = i + 1
		start_port = arg[i]
		end_port = start_port
	elseif p == '-r' then
		i = i + 1
		start_port, end_port = arg[i]:match("(%d+):(%d+)")
	elseif p == '-b' then
		i = i + 1
		backend = arg[i]
		print("Use backend:", backend)
	elseif p == '-l' then
		i = i + 1
		backlog = arg[i]
	end
	i = i + 1
end
start_port = tonumber(start_port)
end_port = tonumber(end_port)
backlog = tonumber(backlog)

local handler = require'handler'
local poll = handler.init{ backend = backend }
local httpserver = require'handler.http.server'

local cnt = 1
local function on_finished(req, resp)
	local content = 'Hello,world!\n'
	resp:set_status(200)
	resp:set_header('Content-Type', "text/plain")
	resp:set_header('Content-Length', #content)
	resp:set_body(content)
	resp:send()
	--[[
	cnt = cnt + 1; if cnt >= 4000 then
		collectgarbage"collect"
		cnt = 1
		print("GCed: mem=", collectgarbage"count")
	end
	--]]
	--cnt = cnt + 1; if cnt >= 300000 then handler.stop() end
end

local function on_request(server, req, resp)
	-- add callbacks to request.
	--req.on_finished = on_finished
	return on_finished(req, resp)
end

local timeout = 20.0
local server = httpserver.new({
	-- set HTTP Server's "name/version" string.
	name = 'Bench',
	send_min_headers = true,
	-- new request callback.
	on_request = on_request,
	-- timeouts
	request_head_timeout = timeout * 1.0,
	request_body_timeout = timeout * 1.0,
	write_timeout = timeout * 1.0,
	keep_alive_timeout = timeout * 1.0,
	max_keep_alive_requests = 1000000,
})

local function make_uri(port, backlog)
	return string.format('tcp://0.0.0.0:%i/?backlog=%i', port, backlog)
end

for port=start_port,end_port do
	print("HTTP server listen on:", port)
	server:listen_uri(make_uri(port, backlog))
end

local stat_timer = poll:create_timer({
on_timer = function()
	print("mem:", collectgarbage"count")
	collectgarbage"step"
end,
}, 4, 4)
stat_timer:start()

local luastate = require"luastate"

local io_stdin = {
on_io_read = function(self)
  local line = io.read("*l")
	print("CMD:", line)
  if line:lower() == "quit" then
		handler.stop()
  elseif line:lower() == "dump" then
		local fd = io.stdout
		collectgarbage"stop"
		luastate.dump_stats(fd)
		fd:flush()
		collectgarbage"restart"
  elseif line:lower() == "gc_stop" then
		collectgarbage"stop"
  elseif line:lower() == "gc_restart" then
		collectgarbage"restart"
  elseif line:lower() == "mem" then
		print("mem:", collectgarbage"count")
		collectgarbage"step"
  end
end,
fileno = function() return 0 end,
}
poll:file_read(io_stdin, true)


handler.run()

--[[
local luatrace = require"luatrace"
luatrace.tron()
print("handler.start():", pcall(function()
handler.run()
end))
luatrace.troff()
--]]

--[[
local annotate = require"jit.annotate"
annotate.on()
handler.run()
annotate.off()
annotate.report(io.open("report.txt", "w"))
--]]

--[[
stat_timer = nil
handler = nil
server = nil
poll = nil
collectgarbage"collect"
collectgarbage"collect"
collectgarbage"collect"
collectgarbage"collect"

local luastate = require"luastate"

luastate.dump_stats(io.stdout)
--]]

--os.exit()

