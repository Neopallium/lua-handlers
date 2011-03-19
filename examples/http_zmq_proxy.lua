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

local tconcat = table.concat

local httpserver = require'handler.http.server'
local ev = require'ev'
local loop = ev.Loop.default
local zmq = require'handler.zmq'

local ctx = zmq.init(loop, 1)

if #arg < 1 then
	print('Usage: ' .. arg[0] .. ' <http_bind_uri> <zmq_req_uri>')
	return
end

local http_uri, zmq_uri = arg[1], arg[2]

local client_requests = {}
local next_id = 0

-- define ZMQ response handler
local function zmq_on_msg(sock, data)
	if type(data) ~= 'table' then
		print('INVALID: Response from ZMQ backend:', data)
		return
	end
	-- get req_id from message.
	local req_id = data[1]
	-- validate message envelope
	if req_id:match("^<req_") == nil or data[2] ~= '' then
		print('INVALID: Message envelope :', req_id, data[2])
		return
	end
	-- get http response object for this request.
	local resp = client_requests[req_id]
	if resp == nil then
		-- client timed out.
		print('HTTP client connect closed: ', req_id)
		return
	end
  print("zmq response:\n", unpack(data))
	-- separate each part of a multi-part message with '\n'
	local resp_data = tconcat(data, '\n', 3)
	print('---- request finished, send response')
	resp:set_status(200)
	resp:set_header('Content-Type', 'application/octet-stream')
	resp:set_header('Content-Length', #resp_data)
	resp:set_body(resp_data)
	resp:send()
	-- remove response object from queue.
	client_requests[req_id] = nil
end

-- create XREQ worker
local zxreq = ctx:xreq(zmq_on_msg)

zxreq:identity("<http-zmq-proxy>")
zxreq:connect(zmq_uri)

local function new_http_post_request(req, resp)
	-- create a new client request id
	-- TODO: use smaller req_id values and re-use old ids.
	local req_id = '<req_' .. tostring(next_id) .. '>'
	next_id = next_id + 1

	-- add http response object to 'client_requests' queue.
	client_requests[req_id] = resp
	
	local post_data = ''
	local function http_on_data(req, resp, data)
		if data then
			post_data = post_data .. data
		end
	end

	local function http_on_finished(req, resp)
		print('---- start request body')
		print(post_data)
		zxreq:send({ req_id, "", post_data })
		print('---- end request body')
	end

	local function http_on_close(resp, err)
		print('---- http_on_close')
		client_requests[req_id] = nil
	end

	-- add callbacks to request.
	req.on_data = http_on_data
	req.on_finished = http_on_finished
	req.on_error = http_on_close -- cleanup on in-complete request
	-- add response callbacks.
	resp.on_error = http_on_close -- cleanup on request abort
end

local function on_request(server, req, resp)
	print('---- start request headers: method =' .. req.method .. ', url = ' .. req.url)
	for k,v in pairs(req.headers) do
		print(k .. ": " .. v)
	end
	print('---- end request headers')
	-- POST request
	if req.method == 'POST' then
		new_http_post_request(req, resp)
	else
		-- return 404 Not found error
		resp:set_status(404)
		resp:send()
		return
	end
end

local server = httpserver.new(loop,{
	-- set HTTP Server's "name/version" string.
	name = string.format("ZMQ-HTTPServer/1.0"),
	-- new request callback.
	on_request = on_request,
	-- timeouts
	request_head_timeout = 1.0,
	request_body_timeout = 1.0,
	write_timeout = 1.0,
	keep_alive_timeout = 1.0,
	max_keep_alive_requests = 10,
})

print("HTTP server listen on:", http_uri)
server:listen_uri(http_uri)

loop:loop()

