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
local tinsert = table.insert
local tremove = table.remove

local httpconnection = require"handler.http.client.connection"

local MAX_CONNECTIONS_PER_HOST = 8

local host_mt = {}
host_mt.__index = host_mt

local function remove_connection(connections, dead)
	-- remove dead connection from pool
	for i=1,#connections do
		if connections[i] == dead then
			-- found dead connection.
			tremove(connections, i)
			break
		end
	end
end

function host_mt:remove_connection(dead)
	-- remove dead connection from pool
	remove_connection(self.connections, dead)
	remove_connection(self.idle, dead)
	-- check for queued requests
	local req = tremove(self.requests, 1) -- pop requests in the order they where queued
	if req then
		-- re-process request to create a new connection (since we are now below the max limit).
		return self:queue_request(req)
	end
	-- if we have no more connections to this host
	if #self.connections == 0 then
		-- then remove this host from the cache of host objects.
		self.cache:remove_host(self)
	end
end

function host_mt:put_idle_connection(conn)
	if conn.is_closed then return end
	-- check for queued requests
	local req
	repeat
		req = tremove(self.requests, 1) -- pop requests in the order they where queued
		-- skip cancelled requests.
		if req and not req.is_cancelled then
			return conn:queue_request(req)
		end
	until req == nil
	tinsert(self.idle, conn)
end

function host_mt:retry_request(req, is_push_back)
	-- make sure request is valid.
	if req.is_cancelled then return end
	-- increase retry count
	local count = (req.retries or 0) + 1
	req.retries = count
	if count > 4 then
		-- reached max request retries
		return
	end
	-- queue request
	if is_push_back then
		tinsert(self.requests, 1, req) -- insert at head of request queue
	else
		tinsert(self.requests, req) -- insert at end of request queue
	end
end

function host_mt:queue_request(req)
	-- make sure request is valid.
	if req.is_cancelled then return end
	-- remove a connection from the idle list.
	local conn = tremove(self.idle)
	-- already have an open connection.
	if not conn then
		if #self.connections >= MAX_CONNECTIONS_PER_HOST then
			-- queue request
			tinsert(self.requests, req)
			return
		end
		-- no pooled connection, create a new connection.
		local err
		conn, err = httpconnection(self.client.loop, self)
		if conn == nil then return false, err end
		tinsert(self.connections, conn)
	end
	return conn:queue_request(req)
end

function host_mt:get_tls_context()
	return self.client:get_tls_context()
end

local function new_host(cache, client, scheme, address, port)
	return setmetatable({
		cache = cache,
		client = client,
		is_https = (scheme == 'https'),
		scheme = scheme,
		address = address,
		port = port,
		open = 0,  -- number of open connections (either in the pool or handling a request).
		idle = {},
		connections = {},
		requests = {},
	}, host_mt)
end

local hosts_cache_mt = {}
hosts_cache_mt.__index = hosts_cache_mt

local function host_key(scheme, address, port)
	-- key format "scheme:address:port"
	return scheme .. ':' .. address .. ':' .. port
end

function hosts_cache_mt:remove_host(host)
	local key = host_key(host.scheme, host.address, host.port)
	self.hosts[key] = nil
end

function hosts_cache_mt:get_host(scheme, address, port)
	local key = host_key(scheme, address, port)
	local host = self.hosts[key]
	if not host then
		-- create new host object.
		host = new_host(self, self.client, scheme, address, port)
		self.hosts[key] = host
	end
	return host
end

function hosts_cache_mt:queue_request(req)
	local host = self:get_host(req.scheme, req.host, req.port)
	assert(host,'failed to create host object.')
	return host:queue_request(req)
end

module(...)

function new(client)
	return setmetatable({
		client = client,
		hosts = {},
	}, hosts_cache_mt)
end

function set_max_connections_per_host(max)
	MAX_CONNECTIONS_PER_HOST = max
end

