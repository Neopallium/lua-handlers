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

local nsocket = require"handler.nsocket"
local httpconnection = require"handler.http.connection"
local request = require"handler.http.client.request"
local headers = require"handler.http.headers"
local headers_new = headers.new

local client_mt = {}
client_mt.__index = client_mt

function client_mt:request(req)
	return request.new(self, req)
end

function client_mt:handle_disconnect(conn)
	-- remove dead connection from pool
	local name = conn:get_name()
	if self.pool[name] == conn then
		self.pool[name] = nil
	end
end

function client_mt:put_connection(conn)
	if not conn.is_closed then
		local name = conn:get_name()
		local old = self.pool[name]
		-- for now only pool one connection per "host:port"
		if old then
			-- keep the new one since it should live longer.
			old:close()
		end
		self.pool[name] = conn
	end
end

function client_mt:get_connection(host, port, is_https)
	local name = host .. ":" .. tostring(port)
	local conn = self.pool[name]
	-- already have an open connection.
	if conn then
		-- we don't support pipelining yet, so remove the connection.
		self.pool[name] = nil
	else
		-- no pooled connection, create a new connection.
		conn = httpconnection.client(self.loop, host, port, is_https)
	end
	return conn
end

module'handler.http.client'

function new(loop, client)
	client = client or {}
	client.loop = loop
	client.pool = {}
	-- normalize http headers
	client.headers = headers_new(client.headers)

	-- set User-Agent header
	client.headers['User-Agent'] =
		client.headers['User-Agent'] or client.user_agent or "Lua-Handler HTTPClient/0.1"

	return setmetatable(client, client_mt)
end

