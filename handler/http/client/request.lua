-- Copyright (c) 2010 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local print = print
local assert = assert
local type = type
local pairs = pairs
local http_headers = require'handler.http.headers'
local new_headers = http_headers.new

local request_mt = {}
request_mt.__index = request_mt

module'handler.http.client.request'

function new(client, req, body)
	if type(req) == 'string' then
		req = { url = req, body = body, headers = new_headers() }
	else
		req.headers = new_headers(req.headers)
		-- default port
		req.port = tonumber(req.port) or 80
	end

	-- copy common headers from client.
	local headers = req.headers
	for name,val in pairs(client.headers) do
		if not headers[name] then
			headers[name] = val
		end
	end

	-- default to version 1.1
	req.http_version = req.http_version or 'HTTP/1.1'

	local url = req.url
	if url then
		-- parse url
		local scheme, authority, path =
			url:match('^([^:/?#]+)://([^/?#]*)(.*)$')
		-- parse authority into host:port
		local i = authority:find(':')
		if i then
			-- have host & port
			req.host = authority:sub(1,i-1)
			req.port = tonumber(authority:sub(i+1)) or 80
		else
			-- only have host
			req.host = authority
			req.port = 80
		end
		req.scheme = scheme
	else
		req.scheme = req.scheme or 'http'
	end
	req.path = path or '/'
	-- validate request.
	assert(req.host, "request missing host.")

	-- if method is not set, then use POST if there is a body to send.
	if not req.method then
		req.method = req.body and 'POST' or 'GET'
	end

	-- check if Host header needs to be set.
	if not req.headers.Host and req.http_version == "HTTP/1.1" then
		local host = req.host
		local port = req.port
		if port and port ~= 80 then
			-- none default port add it to the authority
			host = host .. ":" .. tostring(port)
		end
		req.headers.Host = host
	end

	req = setmetatable(req, request_mt)
	-- get http connection.
	local conn = client:get_connection(req.host, req.port, req.scheme == 'https')
	req.conn = conn

	-- send request.
	conn:queue_request(req)

	return req
end

