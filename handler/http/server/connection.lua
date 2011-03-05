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

local pairs = pairs
local format = string.format
local setmetatable = setmetatable
local assert = assert
local tconcat = table.concat
local tremove = table.remove
local tinsert = table.insert

local ltn12 = require"ltn12"

local lhp = require"http.parser"

local connection = require"handler.connection"

local chunked = require"handler.http.chunked"
local chunked = chunked.new

local headers = require"handler.http.headers"
local headers_new = headers.new

local request = require"handler.http.server.request"
local new_request = request.new

local response = require"handler.http.server.response"
local new_response = response.new

local http_status_codes = {
-- Informational 1xx
[100] = "Continue",
[101] = "Switching Protocols",
-- Successful 2xx
[200] = "OK",
[201] = "Created",
[202] = "Accepted",
[203] = "Non-Authoritative Information",
[204] = "No Content",
[205] = "Reset Content",
[206] = "Partial Content",
-- Redirection 3xx
[300] = "Multiple Choices",
[301] = "Moved Permanently",
[302] = "Found",
[303] = "See Other",
[304] = "Not Modified",
[305] = "Use Proxy",
[306] = "(Unused)",
[307] = "Temporary Redirect",
-- Client Error 4xx
[400] = "Bad Request",
[401] = "Unauthorized",
[402] = "Payment Required",
[403] = "Forbidden",
[404] = "Not Found",
[405] = "Method Not Allowed",
[406] = "Not Acceptable",
[407] = "Proxy Authentication Required",
[408] = "Request Timeout",
[409] = "Conflict",
[410] = "Gone",
[411] = "Length Required",
[412] = "Precondition Failed",
[413] = "Request Entity Too Large",
[414] = "Request-URI Too Long",
[415] = "Unsupported Media Type",
[416] = "Requested Range Not Satisfiable",
[417] = "Expectation Failed",
-- Server Error 5xx
[500] = "Internal Server Error",
[501] = "Not Implemented",
[502] = "Bad Gateway",
[503] = "Service Unavailable",
[504] = "Gateway Timeout",
[505] = "HTTP Version Not Supported",
}
-- pre-append status code to reason phrase
for code,reason in pairs(http_status_codes) do
	http_status_codes[code] = tostring(code) .. ' ' .. reason
end

local function call_callback(obj, cb, ...)
	local meth_cb = obj[cb]
	if meth_cb then
		return meth_cb(obj, ...)
	end
	return false
end

local conn_mt = {}
conn_mt.__index = conn_mt

function conn_mt:close()
	local sock = self.sock
	if sock then
		self.sock = nil
		return sock:close()
	end
end

function conn_mt:handle_error(err)
	if err ~= 'closed' then
		-- if a request is being parsed (i.e. the request body is being read)
		local req = self.cur_req
		if req then
			-- then signal an error (i.e. failed to read the whole request body)
			call_callback(req, 'on_error', req.resp, err)
		end
		-- check if a response is being sent
		local resp = self.cur_resp
		if resp then
			-- then signal an error (i.e. failed to write the whole response)
			call_callback(resp, 'on_error', resp.req, err)
		end
	end
	-- close connection on all errors.
	self.is_closed = true
end

function conn_mt:handle_connected()
end

function conn_mt:handle_data(data)
	local parser = self.parser
	local bytes_parsed = parser:execute(data)
	if parser:is_upgrade() then
		-- TODO: handle upgrade
		-- protocol changing.
		return
	elseif #data ~= bytes_parsed then
		-- failed to parse response.
		self:handle_error(format("http-parser: failed to parse all received data=%d, parsed=%d",
			#data, bytes_parsed))
	end
end

function conn_mt:handle_drain()
	-- write buffer is empty, send more of the request body.
	self:send_body()
end

local function gen_headers(data, headers)
	local offset=#data
	for k,v in pairs(headers) do
		offset = offset + 1
		data[offset] = k
		offset = offset + 1
		data[offset] = ": "
		offset = offset + 1
		data[offset] = v
		offset = offset + 1
		data[offset] = "\r\n"
	end
	return offset
end

-- create a place-holder continue response object.
local continue_resp = { _is_ready_to_send = true }

local function conn_send_response(self, resp)
	-- check for '100 Continue' response marker.
	if resp == continue_resp then
		self.sock:send('HTTP/1.1 100 Continue\r\n\r\n')
		return
	end
	self.cur_resp = resp
	-- check for error/redirection responses.
	local status = tonumber(resp.status or 200)
	if status >= 300 then
		call_callback(self.server, 'on_error_response', resp)
	end
	-- gen: Response-Line
		-- response http version
	local http_version = 'HTTP/1.1'
	if resp.http_version then
		http_version = resp.http_version
	end
	local status_code
	if resp.reason then
		status_code = tostring(status) .. ' ' .. resp.reason
	else
		status_code = http_status_codes[status] or (tostring(status))
	end
	local data = { http_version, " ", status_code, "\r\n" }
	-- preprocess response body
	self:preprocess_body()
	-- gen: Response-Headers
	local offset = gen_headers(data, resp.headers)
	offset = offset + 1
	-- end: Response-Headers
	data[offset] = "\r\n"
	-- send response.
	self.sock:send(tconcat(data))
	-- send response body
	self:send_body()
end

function conn_mt:send_continue(resp)
	local queue = self.response_queue
	-- find parent response
	for i=1,#queue do
		if queue[i] == resp then
			-- if the parent response is at the top of the queue
			if i == 1 then
				-- then send the continue response now.
				conn_send_response(self, continue_resp)
			else
				-- else insert the continue response before it's parent response.
				tinsert(queue, continue_resp, i)
			end
		end
	end
end

function conn_mt:send_response(resp)
	-- check if there is no response being sent right now.
	if self.cur_resp == nil then
		local queue = self.response_queue
		-- if this response is at the to of the response queue, then send it now.
		if queue[1] == resp then
			tremove(queue, 1) -- pop it from the queue first.
			return conn_send_response(self, resp)
		end
	end
	-- can't send response yet, there are other response that
	-- need to be sent before we can send this one.
	-- So mark this response as ready to send.
	resp._is_ready_to_send = true
end

-- this need to be called before writting headers.
function conn_mt:preprocess_body()
	local resp = self.cur_resp
	local body = resp.body
	-- if no response body, then we are finished.
	if not body then
		return self:response_complete()
	end

	local body_type = resp.body_type
	local src
	if body_type == 'string' then
		src = ltn12.source.string(body)
	elseif body_type == 'object' then
		src = body:get_source()
	else
		-- body is the LTN12 source
		src = body
	end

	-- if no Content-Length, then use chunked transfer encoding.
	if not resp.headers['Content-Length'] then
		resp.headers['Transfer-Encoding'] = 'chunked'
		-- add chunked filter.
		src = chunked(src)
	end

	self.body_src = src
end

function conn_mt:send_body()
	local body_src = self.body_src
	local sock = self.sock
	-- check if there is anything to send
	if body_src == nil then return end

	-- send chunks until socket blocks.
	local chunk, num, err
	local len = 0
	repeat
		-- get next chunk
		chunk, err = body_src()
		if chunk == nil then
			return self:response_complete()
		end
		if chunk ~= "" then
			-- send chunk
			num, err = sock:send(chunk)
			if num then len = len + num end
		end
	until err
end

function conn_mt:response_complete()
	-- finished sending response body.
	self.body_src = nil
	-- call response_sent callback.
	call_callback(self.cur_resp, 'on_response_sent')
	self.cur_resp = nil
	-- check if next queue response is ready
	local queue = self.response_queue
	local resp = queue[1]
	if resp and resp._is_ready_to_send then
		-- pop response from queue
		tremove(queue, 1)
		-- and send it.
		return conn_send_response(self, resp)
	end
end

local function create_request_parser(self)
	local req
	local resp
	local headers
	local parser
	local body
	local need_close

	function self.on_message_begin()
		-- setup request object.
		req = new_request()
		headers = req.headers
		body = nil
		need_close = false
	end

	function self.on_url(url)
		-- request method, url
		req.method = parser:method()
		req.url = url
	end

	function self.on_path(path)
		req.path = path
	end

	function self.on_query_string(query_string)
		req.query_string = query_string
	end

	function self.on_fragment(fragment)
		req.fragment = fragment
	end

	function self.on_header(header, val)
		headers[header] = val
	end

	function self.on_headers_complete()
		req.major, req.minor = parser:version()
		-- check if we need to close the connection at the end of the response.
		if not parser:should_keep_alive() then
			need_close = true
		end
		-- track the current request during read of the request body.
		self.cur_req = req
		-- create response object
		resp = new_response(self, req, self.server.headers)
		req.resp = resp
		-- queue response object to maintain the order in which responses
		-- need to be sent out.
		local queue = self.response_queue
		queue[#queue + 1] = resp
		-- check for "Expect: 100-continue" header
		local expect = req.headers['Expect']
		if expect and expect:find("100-continue",1,true) then
			-- call the server's 'on_check_continue' callback
			call_callback(self.server, 'on_check_continue', req, resp)
		else
			-- call the server's 'on_request' callback
			call_callback(self.server, 'on_request', req, resp)
		end
	end

	function self.on_body(data)
		if req.stream_response then
			-- call request's 'on_data' callback on each request body chunk
			call_callback(req, 'on_data', resp, data)
		else
			-- call request's 'on_data' callback only on the full request body.
			if data == nil then
				call_callback(req, 'on_data', resp, body)
				body = nil
			else
				body = (body or '') .. data
			end
		end
	end

	function self.on_message_complete()
		-- We are finished reading the current request.
		self.cur_req = nil
		-- call request's on_finished callback
		call_callback(req, 'on_finished', resp)
		resp = nil
		headers = nil
		self.resp = nil
		body = nil
	end

	parser = lhp.request(self)
	self.parser = parser
end

module(...)

function new(server, sock)
	local self = setmetatable({
		sock = sock,
		server = server,
		is_closed = false,
		response_queue = {},
	}, conn_mt)

	create_request_parser(self)

	-- set this HTTP connection object as the socket's handler.
	sock:sethandler(self)

	return self
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

