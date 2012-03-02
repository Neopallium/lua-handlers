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
local print = print
local assert = assert
local date = os.date
local floor = math.floor

local ev = require"ev"

local acceptor = require"handler.acceptor"

local headers = require"handler.http.headers"
local headers_new = headers.new

local connection = require"handler.http.server.hconnection"

local error_handler = require"handler.http.server.error_handler"

local server_mt = {}
server_mt.__index = server_mt

function server_mt:new_connection(sock)
	local conn = connection(self, sock)
end

function server_mt:add_acceptor(accept)
	local list = self.acceptors
	list[#list+1] = accept
	return true
end

function server_mt:listen_unix(path, backlog)
	assert(path, "You must provide a port/path.")
	return self:add_acceptor(acceptor.unix(self.loop, self.accept_handler, path, backlog))
end

local function check_port_addr(port, addr)
	assert(port, "You must provide a port/path.")
	if type(port) == 'string' then
		local path = port
		port = tonumber(path)
		if port == nil then
			return self:listen_path(path)
		end
	end
	addr = adrr or '0.0.0.0'
	return port, addr
end

function server_mt:listen(port, addr, backlog)
	port, addr = check_port_addr(port, addr)
	return self:add_acceptor(acceptor.tcp(self.loop, self.accept_handler, addr, port, backlog))
end

function server_mt:listen6(port, addr, backlog)
	port, addr = check_port_addr(port, addr)
	return self:add_acceptor(acceptor.tcp6(self.loop, self.accept_handler, addr, port, backlog))
end

function server_mt:tls_listen(tls, port, addr, backlog)
	port, addr = check_port_addr(port, addr)
	return self:add_acceptor(
		acceptor.tls_tcp(self.loop, self.accept_handler, addr, port, tls, backlog))
end

function server_mt:tls_listen6(tls, port, addr, backlog)
	port, addr = check_port_addr(port, addr)
	return self:add_acceptor(
		acceptor.tls_tcp6(self.loop, self.accept_handler, addr, port, tls, backlog))
end

function server_mt:listen_uri(uri, backlog)
	-- we don't support HTTP over UDP.
	assert(not uri:match('^udp'), "Can't accept HTTP connections from UDP socket.")
	-- default port
	local port = 80
	if uri:match('^tls') then
		port = 443 -- default port for https
	end
	return self:add_acceptor(
		acceptor.uri(self.loop, self.accept_handler, uri, backlog, port))
end

local function server_update_cached_date(self, now)
	local cached_date
	-- get new date
	cached_date = date('!%a, %d %b %Y %T GMT')
	self.cached_date = cached_date
	self.cached_now = floor(now) -- only cache now as whole seconds.
	return cached_date
end

function server_mt:update_cached_date()
	return server_update_cached_date(self, self.loop:now())
end

function server_mt:get_cached_date()
	local now = floor(self.loop:now())
	if self.cached_now ~= now then
		return server_update_cached_date(self, now)
	end
	return self.cached_date
end

module(...)

local function default_on_check_continue(self, req, resp)
	-- default to always sending the '100 Continue' response.
	resp:send_continue()
	return self:on_request(req, resp)
end

function new(loop, self)
	self = self or {}
	self.acceptors = {}
	self.loop = loop
	-- default timeouts
		-- maximum time to wait from the start of the request to the end of the headers.
	self.request_head_timeout = self.request_head_timeout or 1.0
		-- maximum time to wait from the end of the request headers to the end of the request body.
	self.request_body_timeout = self.request_body_timeout or -1
		-- maximum time to wait on a blocked write (i.e. with pending data to write).
	self.write_timeout = self.write_timeout or 30.0
		-- maximum time to wait for next request on a connection.
	self.keep_alive_timeout = self.keep_alive_timeout or 5.0
		-- maximum number of requests to allow on one connection.
	self.max_keep_alive_requests = self.max_keep_alive_requests or 128
	-- normalize http headers
	self.headers = headers_new(self.headers)

	-- create accept callback function.
	self.accept_handler = function(sock)
		return self:new_connection(sock)
	end

	-- add a default error_handler if none exists.
	local custom_handler = self.on_error_response
	if custom_handler then
		-- wrap custom handler.
		self.on_error_response = function(self, resp)
			local stat = custom_handler(self, resp)
			-- check if custom error handler added a response body.
			if not stat or resp.body == nil then
				-- try default handler.
				return error_handler(self, resp)
			end
			return stat
		end
	else
		-- no handler, use default
		self.on_error_response = error_handler
	end

	-- add a default on_check_continue handler if none exists.
	if not self.on_check_continue then
		self.on_check_continue = default_on_check_continue
	end

	-- set Server header
	if self.name ~= '' then
		self.headers['Server'] =
			self.headers['Server'] or self.name or "Lua-Handler HTTPServer/0.1"
	end

	return setmetatable(self, server_mt)
end

local default_server = nil
-- get default http server.
function default()
	if not default_server then
		-- create a http server.
		default_server = new(ev.Loop.default)
	end
	return default_server
end

-- initialize default http server.
function init(loop, server)
	default_server = new(loop, server)
end

