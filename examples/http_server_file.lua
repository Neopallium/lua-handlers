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

local lfs = require'lfs'

local ltn12 = require'ltn12'

local tremove = table.remove

local filename = 'index.html'
local filesize = 0

local function on_request(server, req, resp)
	print('---- request finished, send response')
	resp:set_header("Content-Disposition", "attachment; filename=" .. filename)
	resp:set_header('Content-Type', 'application/octet-stream')
	resp:set_header('Content-Length', filesize)
	resp:set_body(ltn12.source.file(io.open(filename, 'rb')))
	resp:set_status(200)
	resp:send()
	resp.on_error = function(resp, req, err)
		print('error sending http response:', err)
	end
end

local server = httpserver.new(loop, {
	-- new request callback.
	on_request = on_request,
	-- timeouts
	request_head_timeout = 1.0,
	request_body_timeout = 1.0,
	write_timeout = 1.0,
	keep_alive_timeout = 1.0,
	max_keep_alive_requests = 10,
})

-- get filename from command line.
if #arg >= 1 then
	filename = tremove(arg, 1)
end

filesize = assert(lfs.attributes(filename, 'size'))

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

