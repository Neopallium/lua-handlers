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

local handler = require"handler"
local poll = handler.get_poller()

local lhp = require"http.parser"
local get_request_parser

local new_buffer = require"handler.buffer".new

local connection = require"handler.connection"

local chunked = require"handler.http.chunked"
local chunked = chunked.new

local headers = require"handler.http.headers"
local headers_new = headers.new
local gen_headers_buf = headers.gen_headers_buf

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
	self.is_closed = true
	local sock = self.sock
	if sock then
		self.sock = nil
		-- kill timer.
		self.timer:stop()
		sock:close()
		if self.parser then
			self.parser:reset()
		end
		self.server:remove_connection(self)
	end
end

local function conn_raise_error(self, err)
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
	-- raise error on all pending responses.
	local queue = self.response_queue
	for i=1,#queue do
		resp = queue[i]
		-- then signal an error (i.e. connection closed/timed out)
		call_callback(resp, 'on_error', resp.req, err)
	end
end

local function conn_set_next_timeout(self, timeout, reason)
	local timer = self.timer
	if timeout < 0 then
		-- disable timer
		timer:stop()
		return
	end
	-- change timer's timeout and start it.
	timer:again(timeout)
	self.timeout_reason = reason
end

function conn_mt:on_timer(timer)
	-- disable timer
	timer:stop()
	-- raise error with timeout reason.
	conn_raise_error(self, self.timeout_reason or 'timeout')
	-- shutdown http connection
	self:close()
end

function conn_mt:handle_error(err)
	conn_raise_error(self, err)
	-- close connection on all errors.
	self:close()
end

function conn_mt:handle_data(data)
	local parser = self.parser or get_request_parser(self)
	local bytes_parsed = parser:execute(data)
	if #data ~= bytes_parsed then
		-- failed to parse response.
		self:handle_error(format("http-parser: failed to parse all received data=%d, parsed=%d",
			#data, bytes_parsed))
	elseif parser.finished then
		-- put parser back into pool
		parser:reset()
	end
end

function conn_mt:handle_drain()
	-- write buffer is empty, send more of the request body.
	self:send_body()
end

-- create a place-holder continue response object.
local continue_resp = { _is_ready_to_send = true }

local resp_tmp_buf = new_buffer(8 * 1024)
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
	local buf = resp_tmp_buf
	buf:reset() -- clear old data.
	buf:append_data(http_version)
	buf:append_data(" ")
	if resp.reason then
		buf:append_data(tostring(status))
		buf:append_data(" ")
		buf:append_data(resp.reason)
	else
		buf:append_data(http_status_codes[status] or (tostring(status)))
	end
	buf:append_data("\r\n")
	-- preprocess response body
	self:preprocess_body()
	-- check for 'Date' header.
	local headers = resp.headers
	if not self.send_min_headers and not headers.Date then
		headers.Date = self.server:get_cached_date()
	end
	-- Is the connection closing after this response?
	if self.need_close and #self.response_queue == 0 then
		headers.Connection = 'close'
	end
	-- gen: Response-Headers
	gen_headers_buf(buf, headers)
	-- end: Response-Headers
	buf:append_data("\r\n")
	local body_src = self.body_src
	if self.body_type == 'string' then
		-- send response headers and response body.
		buf:append_data(body_src)
		self.sock:send(buf:tostring())
		return self:response_complete()
	else
		-- send just response headers
		self.sock:send(buf:tostring())
	end
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
				-- pop it from the queue first.
			if #queue == 1 then
				queue[1] = nil
			else
				tremove(queue, 1)
			end
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
		src = body
	elseif body_type == 'object' then
		src = body:get_source()
	else
		-- body is the LTN12 source
		src = body
	end

	-- if no Content-Length, then use chunked transfer encoding.
	if not resp.headers['Content-Length'] then
		if body_type ~= 'string' then
			resp.headers['Transfer-Encoding'] = 'chunked'
			-- add chunked filter.
			src = chunked(src)
		else
			resp.headers['Content-Length'] = #src
		end
	end

	self.body_src = src
	self.body_type = body_type
end

function conn_mt:send_body()
	local body_src = self.body_src
	local sock = self.sock
	if self.body_type == 'string' then
		sock:send(body_src)
		return self:response_complete()
	end
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
	-- check if the connection is closing.
	if self.need_close then
		self:close()
		return
	end
	-- if no pending responses
	if #queue == 0 then
		-- then start keep-alive idle timeout
		conn_set_next_timeout(self, self.keep_alive_timeout, "keep-alive timeout")
	end
end

local parser_pool = {}

local parser_cnt = 0
local function create_request_parser()
	local req
	local resp
	local headers
	local body
	local hconn
	local lhp_parser
	local ignore = false
	local parser = { finished = false }

	function parser:init(http_conn)
		ignore = false
		hconn = http_conn
		hconn.parser = parser
	end

	function parser:reset()
		ignore = true
		req = nil
		resp = nil
		headers = nil
		body = nil
		hconn.resp = nil
		hconn.parser = nil
		hconn = nil
		parser.finished = false
		lhp_parser:reset()
		parser_pool[#parser_pool + 1] = self
	end

	function parser:execute(data)
		return lhp_parser:execute(data)
	end

	function parser.on_message_begin()
		if ignore then return end
		-- update timeout
		conn_set_next_timeout(hconn, hconn.request_head_timeout, "Read HTTP Request timed out.")
		-- setup request object.
		req = new_request()
		headers = req.headers
		body = nil
		hconn.need_close = false
	end

	function parser.on_url(url)
		if not req then return end
		-- request method, url
		req.method = lhp_parser:method()
		req.url = url
	end

	function parser.on_header(header, val)
		if not headers then return end
		headers[header] = val
	end

	function parser.on_headers_complete()
		if not req then return end
		-- update timeout
		conn_set_next_timeout(hconn, hconn.request_body_timeout, "Read HTTP Request body timed out.")

		req.major, req.minor = lhp_parser:version()
		-- check if we need to upgrade the connection.
		if lhp_parser:is_upgrade() then
			-- TODO: handle upgrade
			-- protocol changing.
			hconn.upgrade = true
		end
		-- check if we need to close the connection at the end of the response.
		if not lhp_parser:should_keep_alive() then
			hconn.need_close = true
		end
		-- is the connection allowed to handle more requests?
		local max_requests = hconn.max_requests - 1
		if max_requests <= 0 then
			hconn.need_close = true
		else
			hconn.max_requests = max_requests
		end
		-- track the current request during read of the request body.
		hconn.cur_req = req
		-- create response object
		resp = new_response(hconn, req, hconn.server.headers)
		req.resp = resp
		-- queue response object to maintain the order in which responses
		-- need to be sent out.
		local queue = hconn.response_queue
		queue[#queue + 1] = resp
		-- check for "Expect: 100-continue" header
		local expect = req.headers['Expect']
		if expect and expect:find("100-continue",1,true) then
			-- call the server's 'on_check_continue' callback
			call_callback(hconn.server, 'on_check_continue', req, resp)
		else
			-- call the server's 'on_request' callback
			call_callback(hconn.server, 'on_request', req, resp)
		end
	end

	function parser.on_body(data)
		if not req then return end
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

	function parser.on_message_complete()
		if not req then return end
		-- We are finished reading the current request.
		hconn.cur_req = nil
		-- call request's on_finished callback
		call_callback(req, 'on_finished', resp)
		if hconn == nil then return end
		req = nil
		resp = nil
		headers = nil
		hconn.resp = nil
		body = nil
		-- are we closing the connection?
		if hconn.need_close then
			ignore = true
			local sock = hconn.sock
			if sock then
				hconn.sock:shutdown(true, false) -- shutdown reads, but not writes.
			end
			return
		end
		-- cancel last timeout
		conn_set_next_timeout(hconn, -1)
		-- finished parser an http request.
		parser.finished = true
	end

	lhp_parser = lhp.request(parser)
	return parser
end

function get_request_parser(http_conn)
	local parser
	local n = #parser_pool
	if n > 0 then
		parser = parser_pool[n]
		parser_pool[n] = nil
	else
		parser = create_request_parser()
	end
	parser:init(http_conn)
	return parser
end

module(...)

function new(server, sock)
	local write_timeout = server.write_timeout or -1
	local self = setmetatable({
		sock = sock,
		server = server,
		is_closed = false,
		response_queue = {},
		-- copy timeouts from server
		request_head_timeout = server.request_head_timeout or -1,
		request_body_timeout = server.request_body_timeout or -1,
		write_timeout = write_timeout,
		keep_alive_timeout = server.keep_alive_timeout or -1,
		max_requests = server.max_keep_alive_requests or 0,
		send_min_headers = server.send_min_headers or 0,
	}, conn_mt)

	-- enable write timeouts on connection.
	if write_timeout > 0 then
		sock:set_write_timeout(write_timeout)
	end

	-- create connection timer.
	self.timer = poll:create_timer(self, 1, 1)

	-- set this HTTP connection object as the socket's handler.
	sock:sethandler(self)

	-- start timeout
	conn_set_next_timeout(self, self.request_head_timeout, "Read HTTP Request timed out.")
	return self
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

