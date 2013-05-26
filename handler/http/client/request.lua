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

local setmetatable = setmetatable
local tonumber = tonumber
local tostring = tostring
local print = print
local assert = assert
local type = type
local pairs = pairs
local error = error

local http_headers = require'handler.http.headers'
local new_headers = http_headers.new

local uri = require"handler.uri"
local uri_parse = uri.parse

local request_mt = {}
request_mt.__index = request_mt

function request_mt:close()
	self.is_cancelled = true
	if self.connection then
		self.connection:close()
	end
end

local function process_request_body(req)
	local body = req.body
	-- if no request body, then we don't need to do anything.
	if not body then return end

	-- default method to POST when there is a request body.
	req.method = req.method or 'POST'

	-- check if request body is a complex object.
	local b_type = type(body)
	if b_type == 'table' then
		assert(body.is_content_object, "Can't encode generic tables.")
		-- if request body is a form
		if body.object_type == 'form' then
			-- force method to POST and set headers Content-Type & Content-Length
			req.method = 'POST'
			req.headers['Content-Type'] = body:get_content_type()
		end
		-- get content-type from object
		if not req.headers['Content-Type'] then
			req.headers['Content-Type'] = body:get_content_type()
		end
		req.headers['Content-Length'] = body:get_content_length()
		-- mark request body as an object
		req.body_type = 'object'
	elseif b_type == 'string' then
		-- simple string body
		req.headers['Content-Length'] = #body
		-- mark request body as an simple string
		req.body_type = 'string'
	elseif b_type == 'function' then
		-- if the body is a function it should be a LTN12 source
		-- mark request body as an source
		req.body_type = 'source'
	else
		assert(false, "Unsupported request body type: " .. b_type)
	end

end

module(...)

function new(client, req, body)
	if type(req) == 'string' then
		req = { url = req, body = body, headers = http_headers.dup(client.headers) }
	else
		req.headers = http_headers.copy_defaults(req.headers, client.headers)
		-- convert port to number
		req.port = tonumber(req.port)
	end

	-- mark request as non-cancelled.
	req.is_cancelled = false

	-- default to version 1.1
	req.http_version = req.http_version or 'HTTP/1.1'

	local url = req.url
	if url then
		if type(url) ~= 'string' then
			return nil, "Invalid request URL: " .. tostring(url)
		end
		-- parse url
		uri_parse(url, req, true) -- parsed parts of url are saved into the 'req' table.
	else
		req.path = req.path or '/'
	end
	-- validate scheme
	local scheme = req.scheme or 'http'
	local default_port
	scheme = scheme:lower()
	if scheme == 'http' then
		default_port = 80
	elseif scheme == 'https' then
		default_port = 443
	else
		error("Unknown protocol scheme in URL: " .. scheme)
	end
	if req.port == nil then
		req.port = default_port
	end
	-- validate request.
	if req.host == nil then
		return nil, "Invalid request missing host or URL."
	end

	-- check if Host header needs to be set.
	if not req.headers.Host and req.http_version == "HTTP/1.1" then
		local host = req.host
		local port = req.port
		if port and port ~= default_port then
			-- none default port add it to the authority
			host = host .. ":" .. tostring(port)
		end
		req.headers.Host = host
	end

	--
	-- Process request body.
	--
	process_request_body(req)

	-- default to GET method.
	req.method = req.method or 'GET'

	return setmetatable(req, request_mt)
end

