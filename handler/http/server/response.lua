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

local setmetatable = setmetatable

local http_headers = require'handler.http.headers'
local dup_headers = http_headers.dup

local response_mt = {}
response_mt.__index = response_mt

function response_mt:set_status(status, reason)
	self.status = status
	self.reason = reason
end

function response_mt:set_header(key, value)
	self.headers[key] = value
end

function response_mt:get_header(key, value)
	self.headers[key] = value
end

function response_mt:set_body(body)
	-- if no response body, then we don't need to do anything.
	if not body then return end
	self.body = body

	-- check if response body is a complex object.
	local b_type = type(body)
	if b_type == 'table' then
		assert(body.is_content_object, "Can't encode generic tables.")
		-- get content-type from object
		if not self.headers['Content-Type'] then
			self.headers['Content-Type'] = body:get_content_type()
		end
		self.headers['Content-Length'] = body:get_content_length()
		-- mark response body as an object
		self.body_type = 'object'
	elseif b_type == 'string' then
		-- simple string body
		self.headers['Content-Length'] = #body
		-- mark response body as an simple string
		self.body_type = 'string'
	elseif b_type == 'function' then
		-- if the body is a function it should be a LTN12 source
		-- mark response body as an source
		self.body_type = 'source'
	else
		assert(false, "Unsupported response body type: " .. b_type)
	end

end

function response_mt:send(status, headers)
	if status then
		self:set_status(status)
	end
	if type(headers) == 'table' then
		local resp_headers = self.headers
		for key,value in pairs(headers) do
			resp_headers[key] = value
		end
	end
	-- signal the HTTP connection that this response is ready.
	return self.connection:send_response(self)
end

function response_mt:send_continue()
	return self.connection:send_continue(self)
end

module(...)

function new(conn, req, default_headers)
	return setmetatable({
		connection = conn,
		request = req,
		headers = dup_headers(default_headers),
	}, response_mt)
end

setmetatable(_M, { __call = function(tab, ...) return new(...) end })

