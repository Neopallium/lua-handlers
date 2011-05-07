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

local tremove = table.remove
local tconcat = table.concat
local print = print

local acceptor = require'handler.acceptor'
local ev = require'ev'
local loop = ev.Loop.default

local max_id = 0
local clients = {}
local servers = {}

local function broadcast(...)
	local msg = tconcat({...}, ' ')
	msg = msg .. '\n'
	print('broadcast:', msg)
	--for _,client in pairs(clients) do
	for i=1,max_id do
		local client = clients[i]
		if type(client) == 'table' and client.is_client then
			client:send(msg)
		end
	end
end

local function add_client(client)
	-- get free client id
	local id = clients[0]
	if id then
		-- remove id from free list.
		clients[0] = clients[id]
	else
		-- no free ids, add client to end of the list.
		id = #clients + 1
		if id > max_id then
			max_id = id
		end
	end
	clients[id] = client
	client.id = id
	-- update max id
	broadcast('add_client:', id)
	return id
end

local function remove_client(client)
	local id = client.id
	assert(clients[id] == client, "Invalid client remove.")
	-- add id to free list.
	clients[id] = clients[0]
	clients[0] = id
	broadcast('remove_client:', id)
end

local generic_client_mt = {
is_client = true,
handle_error = function(self, err)
	print('client error:', self.id, ':', err)
	self.timer:stop(loop)
	-- remove client from list.
	remove_client(self)
end,
handle_connected = function(self)
	self.sock:send('Hello from server\n')
end,
handle_data = function(self, data)
	broadcast('msg from: client.' .. tostring(self.id) .. ':', data)
end,
handle_timer = function(self)
	self.sock:send('ping\n')
end,
send = function(self, msg)
	self.sock:send(msg)
end,
}
generic_client_mt.__index = generic_client_mt

-- new generic client
local function new_generic_client(sock)
	local self = setmetatable({}, generic_client_mt)
	self.sock = sock
	sock:sethandler(self)

	-- create timer watcher
	self.timer = ev.Timer.new(function()
		self:handle_timer()
	end, 2.0, 2.0)
	self.timer:start(loop)

	-- add client to list.
	add_client(self)
	return self
end

-- new generic server
local function new_server(uri, handler)
	print('New generic server listen on: ' .. uri)
	servers[#servers + 1] = acceptor.uri(loop, handler, uri)
end

if #arg < 1 then
	new_server('tcp://127.0.0.1:8081/', new_generic_client)
else
	for i=1,#arg do
		new_server(arg[i], new_generic_client)
	end
end

loop:loop()

