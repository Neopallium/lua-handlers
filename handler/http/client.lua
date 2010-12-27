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
local print = print
local assert = assert

local request = require"handler.http.client.request"
local hosts = require"handler.http.client.hosts"
local headers = require"handler.http.headers"
local headers_new = headers.new

local client_mt = {}
client_mt.__index = client_mt

function client_mt:request(req)
	local req = request.new(self, req)

	-- queue request to be processed.
	self.hosts:queue_request(req)

	return req
end

module'handler.http.client'

function new(loop, client)
	client = client or {}
	client.loop = loop
	client.hosts = hosts.new(client)
	-- normalize http headers
	client.headers = headers_new(client.headers)

	-- set User-Agent header
	client.headers['User-Agent'] =
		client.headers['User-Agent'] or client.user_agent or "Lua-Handler HTTPClient/0.1"

	return setmetatable(client, client_mt)
end

