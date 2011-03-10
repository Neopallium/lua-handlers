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

local httpserver = require'handler.http.server'
local ev = require'ev'
local loop = ev.Loop.default
local tremove = table.remove

local function on_data(req, resp, data)
	print('---- start request body')
	if data then io.write(data) end
	print('---- end request body')
end

local function on_finished(req, resp)
	local html = '<html><head><title>Hello, World!</title></head><body>Hello, World!</body></html>'
	print('---- request finished, send response')
	resp:set_status(200)
	resp:set_header('Content-Type', 'text/html')
	resp:set_header('Content-Length', #html)
	resp:set_body(html)
	resp:send()
end

local function on_response_sent(resp)
	print('---- response sent')
end

local function on_request(server, req, resp)
	print('---- start request headers: method =' .. req.method .. ', url = ' .. req.url)
	for k,v in pairs(req.headers) do
		print(k .. ": " .. v)
	end
	print('---- end request headers')
	-- check for '/favicon.ico' requests.
	if req.url:lower() == '/favicon.ico' then
		-- return 404 Not found error
		resp:set_status(404)
		resp:send()
		return
	end
	-- add callbacks to request.
	req.on_data = on_data
	req.on_finished = on_finished
	-- add response callbacks.
	resp.on_response_sent = on_response_sent
end

local server = httpserver.new(loop,{
	-- set HTTP Server's "name/version" string.
	name = string.format("Test-HTTPServer/%f", math.pi),
	-- new request callback.
	on_request = on_request,
	-- timeouts
	request_head_timeout = 1.0,
	request_body_timeout = 1.0,
	write_timeout = 1.0,
	keep_alive_timeout = 1.0,
	max_keep_alive_requests = 10,
})

for i=1,#arg do
	print("HTTP server listen on:", arg[i])
	server:listen_uri(arg[i])
end

if #arg < 1 then
	local default_uri = 'tcp://127.0.0.1:1080/'
	print("HTTP server listen on default port:", default_uri)
	server:listen_uri(default_uri)
end

loop:loop()

