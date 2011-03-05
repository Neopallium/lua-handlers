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
local print = print
local assert = assert

local nixio = require"nixio"

local request = require"handler.http.client.request"
local hosts = require"handler.http.client.hosts"
local headers = require"handler.http.headers"
local headers_new = headers.new

local ev = require"ev"

local client_mt = {}
client_mt.__index = client_mt

function client_mt:request(req)
	local req, err = request.new(self, req)
	if req == nil then return req, err end

	-- queue request to be processed.
	local stat, err = self.hosts:queue_request(req)
	if not stat then return nil, err end

	return req
end

function client_mt:get_tls_context()
	local tls = self.tls
	if not tls then
		-- make default client-side TLS context.
		tls = nixio.tls'client'
		self.tls = tls
	end
	return tls
end

module(...)

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

local default_client = nil
-- get default http client.
function default()
	if not default_client then
		-- create a http client.
		default_client = new(ev.Loop.default)
	end
	return default_client
end

-- initialize default http client.
function init(loop, client)
	default_client = new(loop, client)
end

