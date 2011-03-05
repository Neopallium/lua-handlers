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

local ev = require"ev"

local acceptor = require"handler.acceptor"

local headers = require"handler.http.headers"
local headers_new = headers.new

local connection = require"handler.http.server.connection"

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

function server_mt:listen_url(url, backlog)
	-- we don't support HTTP over UDP.
	assert(not url:match('^udp'), "Can't accept HTTP connections from UDP socket.")
	return self:add_acceptor(
		acceptor.url(self.loop, self.accept_handler, url, backlog, 80))
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
	self.headers['Server'] =
		self.headers['Server'] or self.name or "Lua-Handler HTTPServer/0.1"

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

