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

local pairs = pairs
local format = string.format
local setmetatable = setmetatable
local assert = assert
local tconcat = table.concat

local ltn12 = require"ltn12"

local lhp = require"http.parser"

local connection = require"handler.connection"

local chunked = require"handler.http.chunked"
local chunked = chunked.new

local response = require"handler.http.client.response"
local new_response = response.new

local function call_callback(obj, cb, ...)
	local meth_cb = obj[cb]
	if meth_cb then
		return meth_cb(obj, ...)
	end
end

local client_mt = {}
client_mt.__index = client_mt

local function pool_remove(self)
	local pool = self.pool
	-- remove connection from the pool.
	if pool then
		pool:remove_connection(self)
	end
end

function client_mt:close()
	local sock = self.sock
	if sock then
		self.sock = nil
		sock:close()
	end
	pool_remove(self)
end

function client_mt:handle_error(err)
	local req = self.cur_req
	local resp = self.resp
	-- flush http-parser
	self:handle_data('')
	-- close connection on all errors.
	self.is_closed = true
	if req then
		-- if connection was closed before we received a response
		if not resp then
			local pool = self.pool
			-- then re-queue request in a new connection.
			if pool then
				pool:retry_request(req, true)
			end
			-- don't send closed error to request.
			req = nil
		else
			-- request is active, signal it that there was an error
			call_callback(req, 'on_error', resp, err)
		end
	end
	pool_remove(self)
end

function client_mt:handle_connected()
end

function client_mt:handle_data(data)
	local parser = self.parser
	local bytes_parsed = parser:execute(data)
	if parser:is_upgrade() then
		-- protocol changing.
		return
	elseif #data ~= bytes_parsed then
		-- failed to parse response.
		self:handle_error(format("http-parser: failed to parse all received data=%d, parsed=%d",
			#data, bytes_parsed))
	end
end

function client_mt:handle_drain()
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

function client_mt:queue_request(req)
	assert(self.cur_req == nil, "TODO: no pipeline support yet!")
	self.cur_req = req
	-- request needs a reference to the connection, so it can cancel the request early.
	req.connection = self
	-- gen: Request-Line
	local data = { req.method, " ", req.path, " ", req.http_version, "\r\n" }
	-- preprocess request body
	self:preprocess_body()
	-- gen: Request-Headers
	local offset = gen_headers(data, req.headers)
	offset = offset + 1
	data[offset] = "\r\n"
	-- send request.
	self.sock:send(tconcat(data))
	-- send request body
	if not self.expect_100 then
		self:send_body()
	end

	return true
end

-- this need to be called before writting headers.
function client_mt:preprocess_body()
	local req = self.cur_req
	local body = req.body
	-- if no request body, then we are finished.
	if not body then
		-- make sure there is no body_src left-over from previous request.
		self.body_src = nil
		-- call request_sent callback.
		call_callback(req, 'on_request_sent')
		return
	end

	if not req.no_expect_100 then
		-- set "Expect: 100-continue" header
		req.headers.Expect = "100-continue"
		self.expect_100 = true
	else
		self.expect_100 = false
	end

	local body_type = req.body_type
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
	if not req.headers['Content-Length'] then
		req.headers['Transfer-Encoding'] = 'chunked'
		-- add chunked filter.
		src = chunked(src)
	end

	self.body_src = src
end

function client_mt:send_body()
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
			-- finished sending request body.
			self.body_src = nil
			-- call request_sent callback.
			call_callback(self.cur_req, 'on_request_sent')
			return
		end
		if chunk ~= "" then
			-- send chunk
			num, err = sock:send(chunk)
			if num then len = len + num end
		end
	until err
end

local function create_response_parser(self)
	local resp
	local headers
	local parser
	local body
	local need_close = false

	function self.on_message_begin()
		-- setup response object.
		resp = new_response()
		headers = resp.headers
		self.resp = resp
		body = nil
		need_close = false
	end

	function self.on_header(header, val)
		headers[header] = val
	end

	function self.on_headers_complete()
		-- check if we need to close the connection at the end of the response.
		if not parser:should_keep_alive() then
			need_close = true
		end
		local status_code = parser:status_code()
		-- check for expect_100
		if self.expect_100 and status_code == 100 then
			-- send request body now.
			self:send_body()
			-- don't process message complete event from the "100 Continue" response.
			self.skip_complete = true
			return
		end
		-- save response status.
		resp.status_code = status_code
		-- call request's on_response callback
		return call_callback(self.cur_req, 'on_response', resp)
	end

	function self.on_body(data)
		if self.skip_complete then return end
		local req = self.cur_req
		if req.stream_response then
			-- call request's on_stream_data callback
			call_callback(req, 'on_data', resp, data)
		else
			-- call request's on_data callback
			if data == nil then
				call_callback(req, 'on_data', resp, body)
				body = nil
			else
				body = (body or '') .. data
			end
		end
	end

	function self.on_message_complete()
		if self.skip_complete then
			self.expect_100 = false
			self.skip_complete = false
			return
		end
		local cur_resp = resp
		local req = self.cur_req
		-- dis-connect request object from connection.
		req.connection = nil
		self.cur_req = nil 
		-- clean-up parser and make it ready for next request
		resp = nil
		headers = nil
		self.resp = nil
		body = nil
		-- put connection back into the pool.
		local pool = self.pool
		if pool and not need_close then
			pool:put_idle_connection(self)
		else
			self:close()
		end
		-- call request's on_finished callback
		call_callback(req, 'on_finished', cur_resp)
	end

	parser = lhp.response(self)
	self.parser = parser
end

module(...)

function new(loop, pool)
	local conn = setmetatable({
		is_closed = false,
		pool = pool,
		expect_100 = false,
		skip_complete = false,
	}, client_mt)

	create_response_parser(conn)

	local sock, err
	if pool.is_https then
		sock, err = connection.tls_tcp(loop, conn, pool.address, pool.port, tls, true)
	else
		sock, err = connection.tcp(loop, conn, pool.address, pool.port)
	end
	if sock == nil then return nil, err end
	conn.sock = sock

	return conn
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

