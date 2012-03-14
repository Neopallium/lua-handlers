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

local backend = "llnet"

if #arg >= 1 then
	backend = arg[1]
	print("Use backend:", backend)
	table.remove(arg, 1)
end

local handler = require'handler'
handler.init{ backend = backend }
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
	--cnt = cnt + 1; if cnt >= 40000 then os.exit(); handler.stop() end
end

local function on_request(server, req, resp)
	-- add callbacks to request.
	--req.on_finished = on_finished
	return on_finished(req, resp)
end

local timeout = 4.0
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

for i=1,#arg do
	print("HTTP server listen on:", arg[i])
	server:listen_uri(arg[i])
end

if #arg < 1 then
	local default_uri = 'tcp://127.0.0.1:1080/?backlog=8192'
	print("HTTP server listen on default port:", default_uri)
	server:listen_uri(default_uri)
end

--local luatrace = require"luatrace"
--luatrace.tron()
--print("handler.start():", pcall(function()
handler.run()
--end))
--luatrace.troff()


