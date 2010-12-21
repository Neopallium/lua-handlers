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

local socket = require"socket"
local ev = require"ev"

local acceptor_mt = {
set_accept_max = function(this, max)
	this.accept_max = max
end,
close = function(this)
	this.io:stop(this.loop)
	this.server:close()
end,
}
acceptor_mt.__index = acceptor_mt

local function acceptor_wrap(loop, handler, server, backlog)
	-- create acceptor
	local this = {
		loop = loop,
		handler = handler,
		server = server,
		-- max sockets to try to accept on one event
		accept_max = 100,
		backlog = backlog,
	}
	setmetatable(this, acceptor_mt)

	server:settimeout(0)
	-- create callback closure
	local accept_cb = function()
		repeat
			local sck, err = server:accept()
			if sck then
				handler(sck)
			else
				if err ~= 'timeout' then
				end
				break
			end
		until not err
	end
	-- create IO watcher.
	local fd = server:getfd()
	this.io = ev.IO.new(accept_cb, fd, ev.READ)

	this.io:start(loop)

	return this
end

module(...)

function new(loop, handler, addr, port, backlog)
	-- setup server socket.
	local server = socket.tcp()
	server:settimeout(0)
	assert(server:setoption('reuseaddr', true), 'server:setoption failed')
	-- bind server
	assert(server:bind(addr, port))
	assert(server:listen(backlog or 256))

	-- wrap server socket
	this = acceptor_wrap(loop, handler, server)
	return this
end

function wrap(loop, handler, server)
	-- make server socket non-blocking.
	server:settimeout(0)
	-- wrap server socket
	this = acceptor_wrap(loop, handler, server)
	return this
end

