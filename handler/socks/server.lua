-- Copyright (c) 2014 by Robert G. Jakabosky <bobby@neoawareness.com>
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

local handler = require"handler"
local poll = handler.get_poller()

local acceptor = require"handler.acceptor"

local connection = require"handler.socks.server.srv_connection"
local methods = require"handler.socks.methods"

local server_mt = {}
server_mt.__index = server_mt

function server_mt:new_connection(sock)
	self.client_cnt = self.client_cnt + 1
	self.client_conn_cnt = self.client_conn_cnt + 1
	if self.client_cnt > self.client_concurrent_peak then
		self.client_concurrent_peak = self.client_cnt
	end
	return connection(self, sock)
end

function server_mt:remove_connection(conn)
	if conn.server == self then
		self.client_cnt = self.client_cnt - 1
		if self.client_cnt == 0 then
			print("client_conn_cnt =", self.client_conn_cnt,
				"client_concurrent_peak =", self.client_concurrent_peak)
		end
		conn.server = nil
	end
end

function server_mt:add_acceptor(accept)
	local list = self.acceptors
	list[#list+1] = accept
	return true
end

function server_mt:listen_uri(uri, backlog)
	-- we don't support Socks over UDP.
	assert(not uri:match('^udp'), "Can't accept Socks connections from UDP socket.")
	-- default port
	local port = 1080
	return self:add_acceptor(
		acceptor.uri(self.accept_handler, uri, backlog, port))
end

function server_mt:check_user(user, pass)
	print("Check user/pass:", user, pass)
	return user == self.username and pass == self.password
end

function server_mt:select_method(user_methods)
	local methods = self.methods
	for i=1,user_methods:get_nmethods() do
		local m = user_methods:get_method(i)
		if methods:find_method(m) then
			return m
		end
	end
	return false
end

module(...)

function new(self)
	self = self or {}
	self.acceptors = {}
	-- list of supported methods
	self.methods = methods.new_methods()
	-- username/password?
	if self.username and self.password then
		self.methods:add_method(2) -- support username/password authentication
	else
		self.methods:add_method(0) -- No authentication required
	end
	-- default timeouts
		-- maximum time to wait for authentication to complete.
	self.auth_timeout = self.auth_timeout or 5.0
		-- maximum time to wait for next request on a connection.
	self.keep_alive_timeout = self.keep_alive_timeout or 5.0
		-- maximum number of requests to allow on one connection.
	self.max_keep_alive_requests = self.max_keep_alive_requests or 10
	-- client stats
	self.client_cnt = 0
	self.client_conn_cnt = 0
	self.client_concurrent_peak = 0

	-- create accept callback function.
	self.accept_handler = function(sock)
		return self:new_connection(sock)
	end

	return setmetatable(self, server_mt)
end

local default_server = nil
-- get default socks server.
function default()
	if not default_server then
		-- create a socks server.
		default_server = new()
	end
	return default_server
end

-- initialize default socks server.
function init(server)
	default_server = new(server)
end

